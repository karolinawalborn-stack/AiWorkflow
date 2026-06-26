import Foundation

/// AI 提供商配置（适配层核心）
///
/// 所有接口差异通过此结构体隔离。
/// 值可在设置页修改，也可从 UserDefaults 读取。
struct AIProviderConfig: Sendable {
    var baseURL: String
    var apiKey: String
    var textModel: String
    var imageModel: String
    var customHeaders: [String: String]
    var timeout: TimeInterval

    static let defaultBaseURL = "https://api.lk888.ai/api"
    static let defaultTextModel = "gpt-5.4"
    static let defaultImageModel = "gpt-image-2"
    static let defaultAPIKey = "sk-1c22e331ff128e7f4d62eff86a5e2caccdbb67e07db70011"

    init(
        baseURL: String = Self.defaultBaseURL,
        apiKey: String = Self.defaultAPIKey,
        textModel: String = Self.defaultTextModel,
        imageModel: String = Self.defaultImageModel,
        customHeaders: [String: String] = [:],
        timeout: TimeInterval = 60
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.textModel = textModel
        self.imageModel = imageModel
        self.customHeaders = customHeaders
        self.timeout = timeout
    }

    /// 构造完整请求 URL
    func url(for path: String) -> String {
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let p = path.hasPrefix("/") ? path : "/\(path)"
        return "\(base)\(p)"
    }

    /// 认证头
    var authHeaders: [String: String] {
        var h = customHeaders
        h["Authorization"] = "Bearer \(apiKey)"
        h["Content-Type"] = "application/json"
        return h
    }
}
