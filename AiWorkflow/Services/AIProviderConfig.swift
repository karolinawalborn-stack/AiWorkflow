import Foundation

// ═══════════════════════════════════════════════════════
//  AI 提供商配置（不含任何 OpenAI 假设）
// ═══════════════════════════════════════════════════════

/// 统一的 AI 服务商配置。
/// 所有接口差异通过此结构体隔离——ViewModel 层不直接读取这些值。
struct AIProviderConfig: Sendable {
    var baseURL: String
    var token: String
    var textModelName: String
    var imageModelName: String
    var customHeaders: [String: String]
    var timeout: TimeInterval

    /// 默认值为 AI领航局-内部工具站
    static let `default` = AIProviderConfig(
        baseURL: "https://api.lk888.ai/api",
        token: "sk-1c22e331ff128e7f4d62eff86a5e2caccdbb67e07db70011",
        textModelName: "gpt-5.4",
        imageModelName: "gpt-image-2"
    )

    init(
        baseURL: String,
        token: String,
        textModelName: String,
        imageModelName: String,
        customHeaders: [String: String] = [:],
        timeout: TimeInterval = 120
    ) {
        self.baseURL = baseURL
        self.token = token
        self.textModelName = textModelName
        self.imageModelName = imageModelName
        self.customHeaders = customHeaders
        self.timeout = timeout
    }

    /// 从 UserDefaults 加载（用户可在设置页覆盖）
    static func loadFromDefaults() -> AIProviderConfig {
        let d = UserDefaults.standard
        return AIProviderConfig(
            baseURL: d.string(forKey: "api_base_url") ?? `default`.baseURL,
            token: d.string(forKey: "api_key") ?? `default`.token,
            textModelName: d.string(forKey: "text_model") ?? `default`.textModelName,
            imageModelName: d.string(forKey: "image_model") ?? `default`.imageModelName
        )
    }

    func saveToDefaults() {
        let d = UserDefaults.standard
        d.set(baseURL, forKey: "api_base_url")
        d.set(token, forKey: "api_key")
        d.set(textModelName, forKey: "text_model")
        d.set(imageModelName, forKey: "image_model")
    }
}

// MARK: - URL 构造 & 认证

extension AIProviderConfig {
    /// 安全拼接完整 URL
    func url(for path: String) -> String {
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let p = path.hasPrefix("/") ? path : "/\(path)"
        return "\(base)\(p)"
    }

    /// 认证请求头
    var authHeaders: [String: String] {
        var h = customHeaders
        h["Authorization"] = "Bearer \(token)"
        h["Content-Type"] = "application/json"
        return h
    }
}
