import Foundation

// ═══════════════════════════════════════════════════════
//  AI 提供商配置（文本/图片 接口分离）
// ═══════════════════════════════════════════════════════

/// 统一的 AI 服务商配置。
/// 文本和图片接口可配置不同的 baseURL 和路径。
struct AIProviderConfig: Sendable {
    // ── 文本接口 ──
    var baseURL: String
    var textModelName: String

    // ── 图片接口（独立于文本） ──
    var imageBaseURL: String
    var imageEndpointPath: String
    var imageModelName: String

    // ── 图片参考图配置 ──
    var imageReferenceMode: String
    var referenceImageFieldName: String
    var imagePromptFieldName: String

    // ── 通用 ──
    var token: String
    var customHeaders: [String: String]
    var timeout: TimeInterval

    /// 默认值
    static let `default` = AIProviderConfig(
        baseURL: "https://api.lk888.ai/api",
        token: "sk-1c22e331ff128e7f4d62eff86a5e2caccdbb67e07db70011",
        textModelName: "gpt-5.4",
        imageBaseURL: "https://api.lk888.ai",
        imageEndpointPath: "/v1/media/generate",
        imageModelName: "gpt-image-2",
        imageReferenceMode: "promptOnlyFallback",
        referenceImageFieldName: "image",
        imagePromptFieldName: "prompt"
    )

    init(
        baseURL: String,
        token: String,
        textModelName: String,
        imageBaseURL: String? = nil,
        imageEndpointPath: String? = nil,
        imageModelName: String,
        imageReferenceMode: String = "promptOnlyFallback",
        referenceImageFieldName: String = "image",
        imagePromptFieldName: String = "prompt",
        customHeaders: [String: String] = [:],
        timeout: TimeInterval = 120
    ) {
        self.baseURL = baseURL
        self.token = token
        self.textModelName = textModelName
        self.imageBaseURL = imageBaseURL ?? baseURL
        self.imageEndpointPath = imageEndpointPath ?? "/v1/media/generate"
        self.imageModelName = imageModelName
        self.imageReferenceMode = imageReferenceMode
        self.referenceImageFieldName = referenceImageFieldName
        self.imagePromptFieldName = imagePromptFieldName
        self.customHeaders = customHeaders
        self.timeout = timeout
    }

    /// 从 UserDefaults 加载
    static func loadFromDefaults() -> AIProviderConfig {
        let d = UserDefaults.standard
        return AIProviderConfig(
            baseURL: d.string(forKey: "api_base_url") ?? `default`.baseURL,
            token: d.string(forKey: "api_key") ?? `default`.token,
            textModelName: d.string(forKey: "text_model") ?? `default`.textModelName,
            imageBaseURL: d.string(forKey: "image_base_url") ?? `default`.imageBaseURL,
            imageEndpointPath: d.string(forKey: "image_endpoint_path") ?? `default`.imageEndpointPath,
            imageModelName: d.string(forKey: "image_model") ?? `default`.imageModelName,
            imageReferenceMode: d.string(forKey: "image_reference_mode") ?? `default`.imageReferenceMode,
            referenceImageFieldName: d.string(forKey: "reference_image_field_name") ?? `default`.referenceImageFieldName,
            imagePromptFieldName: d.string(forKey: "image_prompt_field_name") ?? `default`.imagePromptFieldName
        )
    }

    func saveToDefaults() {
        let d = UserDefaults.standard
        d.set(baseURL, forKey: "api_base_url")
        d.set(token, forKey: "api_key")
        d.set(textModelName, forKey: "text_model")
        d.set(imageBaseURL, forKey: "image_base_url")
        d.set(imageEndpointPath, forKey: "image_endpoint_path")
        d.set(imageModelName, forKey: "image_model")
        d.set(imageReferenceMode, forKey: "image_reference_mode")
        d.set(referenceImageFieldName, forKey: "reference_image_field_name")
        d.set(imagePromptFieldName, forKey: "image_prompt_field_name")
    }
}

// MARK: - URL 构造 & 认证

extension AIProviderConfig {
    /// 文本接口完整 URL
    func textURL(for path: String) -> String {
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let p = path.hasPrefix("/") ? path : "/\(path)"
        return "\(base)\(p)"
    }

    /// 图片接口完整 URL（使用独立的 imageBaseURL）
    var imageURLString: String {
        let base = imageBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = imageEndpointPath.hasPrefix("/") ? imageEndpointPath : "/\(imageEndpointPath)"
        return "\(base)\(path)"
    }

    /// 认证请求头
    var authHeaders: [String: String] {
        var h = customHeaders
        h["Authorization"] = "Bearer \(token)"
        h["Content-Type"] = "application/json"
        return h
    }

    // MARK: - 图片尺寸映射

    /// 比例到尺寸的映射表
    static let ratioSizeMap: [(ratio: String, size: String)] = [
        ("1:1", "1024x1024"),
        ("3:4", "1024x1536"),
        ("4:3", "1536x1024"),
        ("9:16", "768x1024"),
        ("16:9", "1024x768"),
    ]

    /// 支持的尺寸列表（用于设置页选择）
    static let supportedSizes: [String] = [
        "1024x1024", "1024x1536", "1536x1024",
        "768x1024", "1024x768", "768x768",
    ]

    /// 根据比例和可选覆盖值计算最终尺寸
    static func resolveImageSize(ratio: String, override: String?) -> String {
        if let ov = override, !ov.isEmpty { return ov }
        // 精确匹配
        if let match = ratioSizeMap.first(where: { $0.ratio == ratio }) {
            return match.size
        }
        // 近似匹配
        let trimmed = ratio.trimmingCharacters(in: .whitespaces)
        for (r, s) in ratioSizeMap {
            if r == trimmed { return s }
        }
        return "1024x1536" // 默认 fallback
    }
}
