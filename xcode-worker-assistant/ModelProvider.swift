//
//  ModelProvider.swift
//  xcode-worker-assistant
//
//  Created by Samuel Chung on 2026/2/1.
//

import Foundation
import SwiftData

// MARK: - 模型供应商类型
enum ProviderType: String, CaseIterable, Codable {
    case zhipu = "zhipu"
    case kimi = "kimi"
    case deepseek = "deepseek"
    case t8star = "t8star"
    case openai = "openai"
    case custom = "custom"
    
    var displayName: String {
        switch self {
        case .zhipu: return "智谱 AI"
        case .kimi: return "Kimi (Moonshot)"
        case .deepseek: return "DeepSeek"
        case .t8star: return "T8Star"
        case .openai: return "OpenAI"
        case .custom: return "自定义"
        }
    }
}

// MARK: - 模型配置
@Model
final class AIModel {
    var id: UUID
    var name: String
    var modelId: String
    var providerType: String
    var apiUrl: String
    var apiKey: String
    var isEnabled: Bool
    var createdAt: Date
    
    init(name: String, modelId: String, providerType: ProviderType, apiUrl: String, apiKey: String, isEnabled: Bool = true) {
        self.id = UUID()
        self.name = name
        self.modelId = modelId
        self.providerType = providerType.rawValue
        self.apiUrl = apiUrl
        self.apiKey = apiKey
        self.isEnabled = isEnabled
        self.createdAt = Date()
    }
    
    var provider: ProviderType {
        get { ProviderType(rawValue: providerType) ?? .custom }
        set { providerType = newValue.rawValue }
    }
}

// MARK: - 服务器配置
@Model
final class ServerConfig {
    var host: String
    var port: Int
    var maxRetries: Int
    var retryDelay: Double // 秒
    var requestTimeout: Double // 秒
    var isRunning: Bool
    var createdAt: Date
    
    init(host: String = "127.0.0.1", port: Int = 3000, maxRetries: Int = 3, retryDelay: Double = 1.0, requestTimeout: Double = 60.0) {
        self.host = host
        self.port = port
        self.maxRetries = maxRetries
        self.retryDelay = retryDelay
        self.requestTimeout = requestTimeout
        self.isRunning = false
        self.createdAt = Date()
    }
}

// MARK: - 请求日志
@Model
final class RequestLog {
    var id: UUID
    var model: String
    var method: String
    var path: String
    var statusCode: Int?
    var duration: Double?
    var errorMessage: String?
    var timestamp: Date
    
    init(model: String, method: String, path: String, statusCode: Int? = nil, duration: Double? = nil, errorMessage: String? = nil) {
        self.id = UUID()
        self.model = model
        self.method = method
        self.path = path
        self.statusCode = statusCode
        self.duration = duration
        self.errorMessage = errorMessage
        self.timestamp = Date()
    }
}

// MARK: - 预设模型配置
extension AIModel {
    static let presets: [(type: ProviderType, name: String, modelId: String, apiUrl: String)] = [
        (.zhipu, "GLM-4.7", "glm-4.7", "https://open.bigmodel.cn/api/paas/v4"),
        (.kimi, "Kimi K2", "kimi-k2-0905-preview", "https://api.moonshot.cn/v1"),
        (.deepseek, "DeepSeek V3", "deepseek-chat", "https://api.deepseek.com"),
        (.deepseek, "DeepSeek Reasoner", "deepseek-reasoner", "https://api.deepseek.com"),
        (.openai, "GPT-4o", "gpt-4o", "https://api.openai.com/v1"),
        (.openai, "GPT-4o Mini", "gpt-4o-mini", "https://api.openai.com/v1"),
    ]
    
    static func createPreset(type: ProviderType, name: String, modelId: String, apiUrl: String, apiKey: String = "") -> AIModel {
        AIModel(name: name, modelId: modelId, providerType: type, apiUrl: apiUrl, apiKey: apiKey)
    }
}
