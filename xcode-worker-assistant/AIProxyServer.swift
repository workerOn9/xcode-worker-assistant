//
//  AIProxyServer.swift
//  xcode-worker-assistant
//
//  Created by Samuel Chung on 2026/2/1.
//

import Foundation
import Network
import OSLog
import Combine
import SwiftData

@MainActor
class AIProxyServer: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()

    @Published var isRunning = false
    @Published var logs: [String] = []
    @Published var currentPort: Int = 3000
    
    private var listener: NWListener?
    private var modelContainer: ModelContainer?
    private let logger = Logger(subsystem: "com.xcode-worker-assistant", category: "AIProxyServer")
    
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()
    
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
    
    func start(port: Int, modelContainer: ModelContainer) throws {
        guard !isRunning else { return }
        
        self.modelContainer = modelContainer
        
        // 尝试启动监听器，如果失败则尝试备用端口
        let portsToTry = [port, 3001, 3002, 3003, 8080, 8081]
        
        for tryPort in portsToTry {
            do {
                try startListener(on: tryPort)
                self.currentPort = tryPort
                addLog("🚀 代理服务器已启动，监听端口: \(tryPort)")
                return
            } catch {
                addLog("⚠️ 端口 \(tryPort) 不可用: \(error.localizedDescription)")
                if tryPort == portsToTry.last {
                    throw error
                }
            }
        }
    }
    
    private func startListener(on port: Int) throws {
        let config = NWParameters.tcp
        config.allowLocalEndpointReuse = true
        config.allowFastOpen = true
        
        // 确保在主线程上创建监听器
        listener = try NWListener(using: config, on: NWEndpoint.Port(integerLiteral: UInt16(port)))
        guard let listener = listener else {
            throw ProxyError.cannotCreateListener
        }
        
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleStateChange(state)
            }
        }
        
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleConnection(connection)
            }
        }
        
        // 使用 DispatchQueue.main 而不是 .global()，避免潜在的权限问题
        listener.start(queue: .main)
        isRunning = true
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        addLog("🛑 代理服务器已停止")
    }
    
    private func handleStateChange(_ state: NWListener.State) {
        switch state {
        case .ready:
            addLog("✅ 服务器准备就绪")
        case .failed(let error):
            addLog("❌ 服务器失败: \(error)")
            // 如果是权限错误，提供更详细的说明
            let nsError = error as NSError
            if nsError.domain == NSPOSIXErrorDomain && nsError.code == 1 {
                addLog("💡 提示: 请检查应用的 entitlements 中是否已添加 'com.apple.security.network.server' 权限")
            }
            stop()
        case .waiting(let error):
            addLog("⏳ 服务器等待中: \(error)")
        default:
            break
        }
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                Task { @MainActor in
                    self.handleRequest(connection)
                }
            case .failed(let error):
                Task { @MainActor in
                    self.addLog("❌ 连接失败: \(error)")
                }
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: .main)
    }
    
    private func handleRequest(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, context, isComplete, error in
            guard let self = self else { return }
            
            if let data = data, !data.isEmpty {
                Task {
                    await self.processHTTPRequest(data: data, connection: connection)
                }
            }
            
            if isComplete || error != nil {
                connection.cancel()
            }
        }
    }
    
    private func processHTTPRequest(data: Data, connection: NWConnection) async {
        guard let requestString = String(data: data, encoding: .utf8) else {
            await sendErrorResponse(connection: connection, statusCode: 400, message: "Invalid request")
            return
        }
        
        let lines = requestString.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else {
            await sendErrorResponse(connection: connection, statusCode: 400, message: "Invalid request")
            return
        }
        
        let components = firstLine.components(separatedBy: " ")
        guard components.count >= 2 else {
            await sendErrorResponse(connection: connection, statusCode: 400, message: "Invalid request")
            return
        }
        
        let method = components[0]
        // 去除查询参数，只保留路径部分
        let path = components[1].components(separatedBy: "?").first ?? components[1]
        
        addLog("📥 \(method) \(path)")
        
        // 解析请求体
        var bodyData: Data?
        if let bodyIndex = lines.firstIndex(where: { $0.isEmpty }) {
            let bodyLines = lines[(bodyIndex + 1)...]
            bodyData = bodyLines.joined(separator: "\r\n").data(using: .utf8)
        }
        
        // 处理不同的路径
        switch path {
        case "/health":
            await sendHealthResponse(connection: connection)
        case "/v1/models":
            addLog("📋 开始处理 /v1/models 请求")
            await sendModelsList(connection: connection)
        case "/v1/chat/completions", "/api/v1/chat/completions", "/v1/messages":
            await handleChatCompletion(connection: connection, bodyData: bodyData)
        default:
            addLog("⚠️ 未知路径: \(path)")
            await sendErrorResponse(connection: connection, statusCode: 404, message: "Not found", path: path)
        }
    }
    
    private func handleChatCompletion(connection: NWConnection, bodyData: Data?) async {
        guard let bodyData = bodyData,
              let requestBody = try? decoder.decode(ChatCompletionRequest.self, from: bodyData) else {
            await sendErrorResponse(connection: connection, statusCode: 400, message: "Invalid request body", path: "/v1/chat/completions")
            return
        }
        
        let modelId = requestBody.model
        
        // 查找模型配置
        guard let modelContainer = modelContainer else {
            await sendErrorResponse(connection: connection, statusCode: 500, message: "Model container not available", path: "/v1/chat/completions")
            return
        }
        
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<AIModel>(
            predicate: #Predicate<AIModel> { model in
                model.modelId == modelId && model.isEnabled
            }
        )
        
        guard let aiModel = try? context.fetch(descriptor).first else {
            await sendErrorResponse(connection: connection, statusCode: 400, message: "Model not found or disabled: \(modelId)", path: "/v1/chat/completions")
            return
        }
        
        // 转发请求到目标API
        await forwardRequest(connection: connection, aiModel: aiModel, requestBody: requestBody)
    }
    
    private func forwardRequest(connection: NWConnection, aiModel: AIModel, requestBody: ChatCompletionRequest) async {
        let startTime = Date()
        
        guard let url = URL(string: "\(aiModel.apiUrl)/chat/completions") else {
            await sendErrorResponse(connection: connection, statusCode: 500, message: "Invalid API URL", path: "/v1/chat/completions")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(aiModel.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 清理消息内容
        var sanitizedBody = requestBody
        sanitizedBody.messages = sanitizeMessages(requestBody.messages)
        
        do {
            request.httpBody = try encoder.encode(sanitizedBody)
        } catch {
            await sendErrorResponse(connection: connection, statusCode: 500, message: "Failed to encode request", path: "/v1/chat/completions")
            return
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let duration = Date().timeIntervalSince(startTime)
            
            if let httpResponse = response as? HTTPURLResponse {
                addLog("📤 响应状态: \(httpResponse.statusCode) (\(String(format: "%.2f", duration))s)")
                
                // 记录日志
                await MainActor.run {
                    let context = ModelContext(modelContainer!)
                    let log = RequestLog(
                        model: aiModel.modelId,
                        method: "POST",
                        path: "/chat/completions",
                        statusCode: httpResponse.statusCode,
                        duration: duration
                    )
                    context.insert(log)
                }
                
                if httpResponse.statusCode == 200 {
                    await sendResponse(connection: connection, data: data)
                } else {
                    await sendResponse(connection: connection, data: data, statusCode: httpResponse.statusCode)
                }
            }
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            addLog("❌ 请求失败: \(error)")
            
            await MainActor.run {
                let context = ModelContext(modelContainer!)
                let log = RequestLog(
                    model: aiModel.modelId,
                    method: "POST",
                    path: "/chat/completions",
                    statusCode: nil,
                    duration: duration,
                    errorMessage: error.localizedDescription
                )
                context.insert(log)
            }
            
            await sendErrorResponse(connection: connection, statusCode: 502, message: "Bad Gateway: \(error.localizedDescription)", path: "/v1/chat/completions")
        }
    }
    
    private func sanitizeMessages(_ messages: [Message]) -> [Message] {
        return messages.map { message in
            var sanitized = message
            if let content = message.content {
                if let contentList = content as? [Any] {
                    // 处理数组类型的内容
                    let parts = contentList.compactMap { part -> String? in
                        if let str = part as? String { return str }
                        if let dict = part as? [String: Any] {
                            return (try? JSONSerialization.data(withJSONObject: dict))
                                .flatMap { String(data: $0, encoding: .utf8) }
                        }
                        return nil
                    }
                    sanitized.content = parts.joined(separator: "\n")
                } else if !(content is String) {
                    sanitized.content = String(describing: content)
                }
            }
            return sanitized
        }
    }
    
    private func sendHealthResponse(connection: NWConnection) async {
        let response: [String: Any] = [
            "status": "ok",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        guard let data = try? JSONSerialization.data(withJSONObject: response) else { return }
        await sendResponse(connection: connection, data: data)
    }
    
    private func sendModelsList(connection: NWConnection) async {
        addLog("🔍 开始获取模型列表")
        
        guard let modelContainer = modelContainer else {
            addLog("❌ Model container 不可用")
            return
        }
        
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<AIModel>(predicate: #Predicate<AIModel> { model in
            model.isEnabled
        })
        
        addLog("📊 正在查询启用的模型...")
        
        guard let models = try? context.fetch(descriptor) else {
            addLog("❌ 查询模型失败")
            return
        }
        
        addLog("📝 找到 \(models.count) 个启用的模型")
        
        let modelList = models.map { model in
            addLog("  - \(model.name) (\(model.modelId))")
            return [
                "id": model.modelId,
                "object": "model",
                "created": Int(model.createdAt.timeIntervalSince1970),
                "owned_by": model.providerType,
                "name": model.name
            ] as [String: Any]
        }
        
        let response: [String: Any] = [
            "object": "list",
            "data": modelList
        ]
        
        addLog("📦 开始编码模型列表响应...")
        
        guard let data = try? JSONSerialization.data(withJSONObject: response) else {
            addLog("❌ 编码模型列表响应失败")
            return
        }
        
        addLog("✅ 模型列表响应已生成，大小: \(data.count) 字节")
        
        await sendResponse(connection: connection, data: data)
        
        addLog("📤 模型列表响应已发送")
    }
    
    private func sendResponse(connection: NWConnection, data: Data, statusCode: Int = 200) async {
        let responseHeaders = [
            "HTTP/1.1 \(statusCode) OK",
            "Content-Type: application/json",
            "Content-Length: \(data.count)",
            "Connection: close",
            "Access-Control-Allow-Origin: *",
            ""
        ].joined(separator: "\r\n")
        
        let responseData = (responseHeaders + "\r\n").data(using: .utf8)! + data
        
        addLog("📡 发送响应，状态码: \(statusCode)，大小: \(responseData.count) 字节")
        
        connection.send(content: responseData, completion: .contentProcessed { error in
            if let error = error {
                self.addLog("❌ 发送响应失败: \(error)")
            } else {
                self.addLog("✅ 响应发送成功")
            }
            connection.cancel()
        })
    }
    
    private func sendErrorResponse(connection: NWConnection, statusCode: Int, message: String, path: String? = nil) async {
        let pathInfo = path != nil ? " [路径: \(path!)]" : ""
        let fullUrl = path != nil ? "http://127.0.0.1:\(currentPort)\(path!)" : ""
        addLog("❌ 发送错误响应: \(statusCode) - \(message)\(pathInfo)")
        if !fullUrl.isEmpty {
            addLog("🔗 完整请求地址: \(fullUrl)")
        }
        
        let errorResponse: [String: Any] = [
            "error": [
                "message": message,
                "type": "api_error"
            ]
        ]
        
        guard let data = try? JSONSerialization.data(withJSONObject: errorResponse) else { return }
        await sendResponse(connection: connection, data: data, statusCode: statusCode)
    }
    
    private func addLog(_ message: String) {
        let timestamp = DateFormatter().string(from: Date())
        let logMessage = "[\(timestamp)] \(message)"
        print(logMessage)
        
        logs.append(logMessage)
        if logs.count > 500 {
            logs.removeFirst()
        }
    }
    
    // MARK: - 模型连通性测试
    func testModelConnection(_ model: AIModel) async throws -> (success: Bool, message: String, duration: TimeInterval) {
        let startTime = Date()
        
        addLog("🧪 开始测试模型连接: \(model.name) (\(model.modelId))")
        addLog("🌐 API URL: \(model.apiUrl)/models")
        
        guard let url = URL(string: "\(model.apiUrl)/models") else {
            let message = "无效的 API URL"
            addLog("❌ \(message)")
            return (false, message, Date().timeIntervalSince(startTime))
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(model.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30.0
        
        addLog("📤 发送请求到 API...")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let duration = Date().timeIntervalSince(startTime)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                let message = "无效的响应"
                addLog("❌ \(message)")
                return (false, message, duration)
            }
            
            addLog("📥 收到响应，状态码: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 200 {
                // 尝试解析响应
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let data = json["data"] as? [[String: Any]] {
                    addLog("✅ 连接成功，找到 \(data.count) 个模型")
                    return (true, "连接成功，找到 \(data.count) 个模型", duration)
                } else {
                    addLog("✅ 连接成功，但响应格式可能不标准")
                    return (true, "连接成功", duration)
                }
            } else if httpResponse.statusCode == 401 {
                let message = "认证失败，请检查 API Key"
                addLog("❌ \(message)")
                return (false, message, duration)
            } else {
                let responseString = String(data: data, encoding: .utf8) ?? "无响应数据"
                addLog("❌ API 返回错误: \(responseString)")
                return (false, "API 返回错误 (状态码: \(httpResponse.statusCode))", duration)
            }
        } catch let error as URLError {
            let duration = Date().timeIntervalSince(startTime)
            let message: String
            switch error.code {
            case .timedOut:
                message = "请求超时"
            case .notConnectedToInternet:
                message = "网络连接失败"
            case .serverCertificateUntrusted:
                message = "服务器证书不受信任"
            default:
                message = "连接失败: \(error.localizedDescription)"
            }
            addLog("❌ \(message)")
            return (false, message, duration)
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            addLog("❌ 未知错误: \(error.localizedDescription)")
            return (false, error.localizedDescription, duration)
        }
    }
    
    // MARK: - 请求/响应模型
    struct ChatCompletionRequest: Codable {
        let model: String
        var messages: [Message]
        var stream: Bool?
        let temperature: Double?
        let maxTokens: Int?
        let topP: Double?
        
        enum CodingKeys: String, CodingKey {
            case model, messages, stream, temperature
            case maxTokens = "max_tokens"
            case topP = "top_p"
        }
    }
    
    struct Message: Codable {
        let role: String
        var content: Any?
        
        enum CodingKeys: String, CodingKey {
            case role, content
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            role = try container.decode(String.self, forKey: .role)
            
            if let stringValue = try? container.decode(String.self, forKey: .content) {
                content = stringValue
            } else if let arrayValue = try? container.decode([String].self, forKey: .content) {
                content = arrayValue
            } else if let arrayValue = try? container.decode([[String: AnyCodable]].self, forKey: .content) {
                content = arrayValue.map { $0.mapValues { $0.value } }
            } else {
                content = nil
            }
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(role, forKey: .role)
            
            if let content = content {
                if let stringValue = content as? String {
                    try container.encode(stringValue, forKey: .content)
                } else if let arrayValue = content as? [[String: AnyCodable]] {
                    try container.encode(arrayValue, forKey: .content)
                } else {
                    // 对于非字符串内容，转为JSON字符串
                    let data = try JSONSerialization.data(withJSONObject: content)
                    let jsonString = String(data: data, encoding: .utf8) ?? ""
                    try container.encode(jsonString, forKey: .content)
                }
            }
        }
    }
    
    enum ProxyError: LocalizedError {
        case cannotCreateListener
        case portInUse(Int)
        
        var errorDescription: String? {
            switch self {
            case .cannotCreateListener:
                return "无法创建监听器"
            case .portInUse(let port):
                return "端口 \(port) 已被占用"
            }
        }
    }
}

// Helper type for encoding Any as JSON
private struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else if let dictValue = try? container.decode([String: AnyCodable].self) {
            value = dictValue.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let intValue as Int:
            try container.encode(intValue)
        case let doubleValue as Double:
            try container.encode(doubleValue)
        case let stringValue as String:
            try container.encode(stringValue)
        case let boolValue as Bool:
            try container.encode(boolValue)
        case let arrayValue as [Any]:
            try container.encode(arrayValue.map { AnyCodable($0) })
        case let dictValue as [String: Any]:
            try container.encode(dictValue.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}

