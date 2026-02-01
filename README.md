# xcode-worker-assistant

想着学习用xcode，但是奈何xcode的自定义大模型接入比较麻烦，启发于项目[learningpro/Xcode-Intelligence-Proxy](https://github.com/learningpro/Xcode-Intelligence-Proxy)，用GLM-4.7重新设计开发了swiftUI的macOS原生APP。

![APP](/readme-imgs/main.png)

## 📋 项目功能总结

> 以下由GLM-4.7生成

Xcode AI Assistant 是一款专为 Xcode 开发者设计的本地 AI 模型代理服务应用，允许开发者通过本地代理服务器访问多个 AI 提供商的 API，主要用于配合 Xcode 的 AI 编程助手功能。

### 核心功能

1. 本地代理服务器
   * 在本地启动 HTTP 代理服务，监听指定端口
   * 支持多端口自动回退（3000, 3001, 3002, 3003, 8080, 8081）
   * 兼容 OpenAI API 格式

2. 多模型支持
   * 支持智谱 AI (GLM-4.7)
   * 支持 Kimi (Moonshot)
   * 支持自定义模型

3. 模型管理
   * 添加、编辑、删除 AI 模型配置
   * 预设模型快速配置
   * 模型启用/禁用切换
   * API 连通性测试

4. 请求日志
   * 实时日志显示
   * 日志过滤搜索
   * 请求耗时统计
   * 错误信息记录

5. 持久化存储
   * 使用 SwiftData 存储模型配置
   * 请求历史记录保存
   * 服务器配置持久化

## 📖 帮助文档

### 快速开始

#### 1. 启动应用

打开应用后，您将看到四个主要标签页：
* 模型 - 管理您的 AI 模型配置
* 服务器 - 控制代理服务器的启动和停止
* 日志 - 查看请求日志
* 设置 - 应用设置和数据管理

#### 2. 配置 AI 模型

方式一：使用预设模型
1. 进入「模型」标签页
2. 点击「+」按钮 → 选择「从预设添加」
3. 选择您需要的模型（如 GLM-4.7、DeepSeek V3 等）
4. 输入对应的 API Key
5. 点击「添加选中的」

方式二：添加自定义模型
1. 进入「模型」标签页
2. 点击「+」按钮 → 选择「自定义模型」
3. 填写模型信息：
    * 名称：自定义名称
    * 模型ID：API 使用的模型标识符
    * 供应商类型：选择对应的提供商
    * API URL：提供商的 API 地址
    * API Key：您的 API 密钥

#### 3. 测试模型连接

1. 在「模型」列表中选择一个模型
2. 在详情页面点击「测试连接」按钮
3. 等待测试结果，确认模型配置正确

#### 4. 启动代理服务器

1. 进入「服务器」标签页
2. 设置监听端口（默认 3000）
3. 点击「启动服务器」
4. 确认服务器状态显示为「运行中」
5. 点击「复制 Xcode 配置」获取环境变量配置

#### 5. 配置 Xcode

在 Xcode 中设置以下环境变量：

1. 打开设置，然后点击`Add a Model Provider`

![set1](/readme-imgs/xcode-set1.png)

2. 选择设置`Locally Hosted`，填写端口（默认3000，APP上可以自定义）

![set2](/readme-imgs/xcode-set2.png)

3. Enjoy!😊

![enjoy](/readme-imgs/xcode-enjoy.png)