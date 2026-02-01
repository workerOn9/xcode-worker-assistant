//
//  ContentView.swift
//  xcode-worker-assistant
//
//  Created by Samuel Chung on 2026/2/1.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var models: [AIModel]
    @Query private var serverConfig: [ServerConfig]
    
    @StateObject private var proxyServer = AIProxyServer()
    @State private var selectedTab = 0
    @State private var showingAddModel = false
    @State private var showingSettings = false
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // 模型管理页面
            ModelsView(proxyServer: proxyServer)
                .tabItem {
                    Label("模型", systemImage: "brain.head.profile")
                }
                .tag(0)
            
            // 服务器控制页面
            ServerControlView(proxyServer: proxyServer)
                .tabItem {
                    Label("服务器", systemImage: "server.rack")
                }
                .tag(1)
            
            // 日志页面
            LogsView(proxyServer: proxyServer)
                .tabItem {
                    Label("日志", systemImage: "doc.text")
                }
                .tag(2)
            
            // 设置页面
            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
                .tag(3)
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}

// MARK: - 模型管理视图
struct ModelsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var models: [AIModel]
    @StateObject var proxyServer: AIProxyServer
    @State private var showingAddModel = false
    @State private var editingModel: AIModel?
    @State private var showingPresets = false
    
    var enabledModels: [AIModel] {
        models.filter { $0.isEnabled }
    }
    
    var body: some View {
        NavigationSplitView {
            List(selection: $editingModel) {
                ForEach(models) { model in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.name)
                                .font(.headline)
                            Text(model.modelId)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(ProviderType(rawValue: model.providerType)?.displayName ?? model.providerType)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.2))
                                .cornerRadius(4)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { model.isEnabled },
                            set: { newValue in
                                model.isEnabled = newValue
                            }
                        ))
                    }
                    .tag(model)
                }
                .onDelete(perform: deleteModels)
            }
            .navigationSplitViewColumnWidth(min: 250, ideal: 300)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button("从预设添加", systemImage: "star") {
                            showingPresets = true
                        }
                        Button("自定义模型", systemImage: "plus") {
                            showingAddModel = true
                        }
                    } label: {
                        Label("添加模型", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if let editingModel = editingModel {
                ModelDetailView(model: editingModel, proxyServer: proxyServer)
            } else {
                ContentUnavailableView {
                    Label("选择模型", systemImage: "brain.head.profile")
                } description: {
                    Text("从列表中选择一个模型查看详情或编辑")
                }
            }
        }
        .sheet(isPresented: $showingAddModel) {
            AddModelView()
        }
        .sheet(isPresented: $showingPresets) {
            PresetModelsView()
        }
    }
    
    private func deleteModels(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(models[index])
            }
        }
    }
}

// MARK: - 模型详情视图
struct ModelDetailView: View {
    @Bindable var model: AIModel
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var proxyServer: AIProxyServer
    
    @State private var isTestingConnection = false
    @State private var testResult: (success: Bool, message: String, duration: TimeInterval)?
    @State private var showingTestResult = false
    
    var body: some View {
        Form {
            Section("基本信息") {
                TextField("名称", text: $model.name)
                TextField("模型ID", text: $model.modelId)
                
                Picker("供应商类型", selection: Binding(
                    get: { model.provider },
                    set: { model.provider = $0 }
                )) {
                    ForEach(ProviderType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
            }
            
            Section("API配置") {
                TextField("API URL", text: $model.apiUrl)
                SecureField("API Key", text: $model.apiKey)
            }
            
            Section {
                Button {
                    testConnection()
                } label: {
                    HStack {
                        if isTestingConnection {
                            ProgressView()
                                .controlSize(.small)
                            Text("测试中...")
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "network")
                            Text("测试连接")
                        }
                    }
                }
                .disabled(isTestingConnection || model.apiUrl.isEmpty || model.apiKey.isEmpty)
                
                if let result = testResult {
                    HStack {
                        Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(result.success ? .green : .red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.success ? "连接成功" : "连接失败")
                                .font(.headline)
                            Text(result.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("耗时: \(String(format: "%.2f", result.duration))s")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("连接测试")
            }
            
            Section("状态") {
                Toggle("启用此模型", isOn: $model.isEnabled)
                HStack {
                    Text("创建时间")
                    Spacer()
                    Text(model.createdAt, format: .dateTime)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(model.name)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    try? modelContext.save()
                }
            }
        }
    }
    
    private func testConnection() {
        isTestingConnection = true
        testResult = nil
        
        Task {
            do {
                let result = try await proxyServer.testModelConnection(model)
                
                await MainActor.run {
                    isTestingConnection = false
                    testResult = result
                }
            } catch {
                await MainActor.run {
                    isTestingConnection = false
                    testResult = (success: false, message: error.localizedDescription, duration: 0)
                }
            }
        }
    }
}

// MARK: - 添加模型视图
struct AddModelView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var modelId = ""
    @State private var providerType: ProviderType = .custom
    @State private var apiUrl = ""
    @State private var apiKey = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("名称", text: $name)
                    TextField("模型ID", text: $modelId)
                    Picker("供应商类型", selection: $providerType) {
                        ForEach(ProviderType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                }
                
                Section("API配置") {
                    TextField("API URL", text: $apiUrl)
                    SecureField("API Key", text: $apiKey)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("添加模型")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        let newModel = AIModel(
                            name: name,
                            modelId: modelId,
                            providerType: providerType,
                            apiUrl: apiUrl,
                            apiKey: apiKey
                        )
                        modelContext.insert(newModel)
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(name.isEmpty || modelId.isEmpty || apiUrl.isEmpty)
                }
            }
        }
    }
}

// MARK: - 预设模型视图
struct PresetModelsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var apiKeys: [String: String] = [:]
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(AIModel.presets.indices, id: \.self) { index in
                    let preset = AIModel.presets[index]
                    VStack(alignment: .leading, spacing: 6) {
                        Text(preset.name)
                            .font(.headline)
                        Text(preset.modelId)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        SecureField("API Key", text: Binding(
                            get: { apiKeys[preset.modelId, default: ""] },
                            set: { apiKeys[preset.modelId] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("预设模型")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加选中的") {
                        for preset in AIModel.presets {
                            if let apiKey = apiKeys[preset.modelId], !apiKey.isEmpty {
                                let newModel = AIModel.createPreset(
                                    type: preset.type,
                                    name: preset.name,
                                    modelId: preset.modelId,
                                    apiUrl: preset.apiUrl,
                                    apiKey: apiKey
                                )
                                modelContext.insert(newModel)
                            }
                        }
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - 服务器控制视图
struct ServerControlView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var serverConfig: [ServerConfig]
    @StateObject var proxyServer: AIProxyServer
    
    @State private var port = 3000
    @State private var showingSettings = false
    
    var config: ServerConfig? {
        serverConfig.first
    }
    
    var body: some View {
        Form {
            Section("服务器状态") {
                HStack {
                    Image(systemName: proxyServer.isRunning ? "circle.fill" : "circle")
                        .foregroundStyle(proxyServer.isRunning ? .green : .red)
                    
                    Text(proxyServer.isRunning ? "运行中" : "已停止")
                        .font(.headline)
                }
                
                if proxyServer.isRunning {
                    HStack {
                        Text("监听端口")
                        Spacer()
                        Text("\(proxyServer.currentPort)")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("监听地址")
                        Spacer()
                        Text("127.0.0.1")
                            .foregroundStyle(.secondary)
                    }
                    
                    // 复制配置按钮
                    Button {
                        copyXcodeConfig()
                    } label: {
                        Label("复制 Xcode 配置", systemImage: "doc.on.doc")
                    }
                }
            }
            
            Section("控制") {
                if proxyServer.isRunning {
                    Button("停止服务器", role: .destructive) {
                        proxyServer.stop()
                    }
                } else {
                    Button("启动服务器") {
                        startServer()
                    }
                }
            }
            
            Section("端口设置") {
                HStack {
                    Text("端口")
                    Spacer()
                    TextField("端口", value: $port, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .disabled(proxyServer.isRunning)
                }
            }
            
            if let config = config {
                Section("高级设置") {
                    NavigationLink {
                        ServerSettingsView(config: config)
                    } label: {
                        Label("高级配置", systemImage: "gearshape.2")
                    }
                }
            }
            
            Section("使用说明") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. 在模型页面配置至少一个AI模型")
                    Text("2. 启动服务器")
                    Text("3. 在 Xcode 中设置环境变量：")
                    Text("   ANTHROPIC_BASE_URL = http://127.0.0.1:\(port)")
                    Text("   ANTHROPIC_AUTH_TOKEN = any-string")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("服务器控制")
    }
    
    private func startServer() {
        do {
            try proxyServer.start(port: port, modelContainer: modelContext.container)
            
            // 保存或更新配置
            if let existingConfig = config {
                existingConfig.port = port
                existingConfig.isRunning = true
            } else {
                let newConfig = ServerConfig(port: port)
                newConfig.isRunning = true
                modelContext.insert(newConfig)
            }
            try? modelContext.save()
        } catch {
            print("启动服务器失败: \(error)")
        }
    }
    
    private func copyXcodeConfig() {
        let config = """
        ANTHROPIC_BASE_URL = http://127.0.0.1:\(proxyServer.currentPort)
        ANTHROPIC_AUTH_TOKEN = any-string
        """
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(config, forType: .string)
    }
}

// MARK: - 服务器高级设置视图
struct ServerSettingsView: View {
    @Bindable var config: ServerConfig
    
    var body: some View {
        Form {
            Section("重试配置") {
                Stepper("最大重试次数: \(config.maxRetries)", value: $config.maxRetries, in: 1...10)
                Stepper("重试延迟: \(Int(config.retryDelay))s", value: $config.retryDelay, in: 0.5...10, step: 0.5)
            }
            
            Section("超时配置") {
                Stepper("请求超时: \(Int(config.requestTimeout))s", value: $config.requestTimeout, in: 10...300, step: 10)
            }
            
            Section("网络") {
                TextField("监听地址", text: $config.host)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("高级配置")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") {
                    
                }
            }
        }
    }
}

// MARK: - 日志视图
struct LogsView: View {
    @ObservedObject var proxyServer: AIProxyServer
    @State private var filterText = ""
    
    var filteredLogs: [String] {
        if filterText.isEmpty {
            return proxyServer.logs
        }
        return proxyServer.logs.filter { $0.localizedCaseInsensitiveContains(filterText) }
    }
    
    var body: some View {
        VStack {
            SearchBar(text: $filterText)
                .padding(.horizontal)
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(filteredLogs.enumerated()), id: \.offset) { index, log in
                        Text(log)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .foregroundStyle(logColor(for: log))
                    }
                }
            }
        }
        .navigationTitle("请求日志")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("清除") {
                    proxyServer.logs.removeAll()
                }
            }
        }
    }
    
    private func logColor(for log: String) -> Color {
        if log.contains("❌") { return .red }
        if log.contains("⚠️") { return .orange }
        if log.contains("✅") { return .green }
        if log.contains("🚀") { return .blue }
        if log.contains("🛑") { return .red }
        return .primary
    }
}

// MARK: - 搜索栏
struct SearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            
            TextField("搜索日志", text: $text)
                .textFieldStyle(.plain)
            
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - 设置视图
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        Form {
            Section("关于") {
                HStack {
                    Text("应用名称")
                    Spacer()
                    Text("Xcode AI Assistant")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("版本")
                    Spacer()
                    Text("1.0.0")
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("数据") {
                Button("清除所有模型配置", role: .destructive) {
                    clearAllModels()
                }
                
                Button("清除所有日志", role: .destructive) {
                    clearAllLogs()
                }
                
                Button("重置所有数据", role: .destructive) {
                    resetAllData()
                }
            }
            
            Section("支持") {
                Link("GitHub 仓库", destination: URL(string: "https://github.com/workerOn9/xcode-worker-assistant")!)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
    }
    
    private func clearAllModels() {
        do {
            let descriptor = FetchDescriptor<AIModel>()
            let models = try modelContext.fetch(descriptor)
            for model in models {
                modelContext.delete(model)
            }
            try modelContext.save()
        } catch {
            print("清除模型失败: \(error)")
        }
    }
    
    private func clearAllLogs() {
        do {
            let descriptor = FetchDescriptor<RequestLog>()
            let logs = try modelContext.fetch(descriptor)
            for log in logs {
                modelContext.delete(log)
            }
            try modelContext.save()
        } catch {
            print("清除日志失败: \(error)")
        }
    }
    
    private func resetAllData() {
        clearAllModels()
        clearAllLogs()
        
        do {
            let descriptor = FetchDescriptor<ServerConfig>()
            let configs = try modelContext.fetch(descriptor)
            for config in configs {
                modelContext.delete(config)
            }
            try modelContext.save()
        } catch {
            print("清除配置失败: \(error)")
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Item.self, AIModel.self, ServerConfig.self, RequestLog.self], inMemory: true)
}
