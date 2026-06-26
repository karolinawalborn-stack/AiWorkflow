import Foundation

// ═══════════════════════════════════════════════════════
//  AI领航局-内部工具站 专用 DTO（与 OpenAI 格式解耦）
// ═══════════════════════════════════════════════════════
//
// 这些类型严格对应内部工具站的 API 格式。
// 如果接口格式变更，只改这个文件，不影响上层。
// ═══════════════════════════════════════════════════════

// MARK: - 文本生成

/// 文本生成请求体（对应 /v1/chat/completions）
struct InternalToolStationTextRequest: Encodable, Sendable {
    /// 模型标识（由 AIProviderConfig.textModelName 提供）
    let model: String
    /// 消息列表（role: system / user / assistant）
    let messages: [InternalTextMessage]
    /// 温度参数
    let temperature: Double
}

struct InternalTextMessage: Codable, Sendable {
    let role: String
    let content: String
}

/// 文本生成响应
struct InternalToolStationTextResponse: Decodable, Sendable {
    let choices: [InternalTextChoice]
}

struct InternalTextChoice: Decodable, Sendable {
    let index: Int
    let message: InternalTextMessage
    /// 结束原因：stop / length / content_filter
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index, message
        case finishReason = "finish_reason"
    }
}

// MARK: - 图片生成

/// 图片生成请求体（对应 /v1/images/generations）
struct InternalToolStationImageRequest: Encodable, Sendable {
    let model: String
    let prompt: String
    let n: Int
    let size: String

    /// 返回格式：url / b64_json
    let responseFormat: String

    enum CodingKeys: String, CodingKey {
        case model, prompt, n, size
        case responseFormat = "response_format"
    }
}

/// 图片生成响应
struct InternalToolStationImageResponse: Decodable, Sendable {
    let data: [InternalImageData]
}

struct InternalImageData: Decodable, Sendable {
    /// URL 形式（responseFormat=url 时返回）
    let url: String?
    /// base64 形式（responseFormat=b64_json 时返回）
    let b64Json: String?
    /// API 优化后的提示词
    let revisedPrompt: String?

    enum CodingKeys: String, CodingKey {
        case url
        case b64Json = "b64_json"
        case revisedPrompt = "revised_prompt"
    }
}

// MARK: - 图片结果（统一格式，兼容 URL / base64 / 二进制）

/// 图片生成结果——适配层统一输出格式
/// ViewModel 和 View 只依赖此类型，不关心底层是 URL 还是 base64。
struct ImageGenerationResult: Sendable {
    /// 图片二进制数据（优先从 base64 解码，URL 模式需额外下载）
    public private(set) var imageData: Data?

    /// 图片 URL（如果 API 返回 URL 形式）
    public private(set) var imageURL: String?

    /// API 优化后的提示词
    public private(set) var revisedPrompt: String?

    /// 从 API 原始数据构造统一结果
    init(from item: InternalImageData, downloadURLData: Data? = nil) {
        // 优先用下载好的二进制
        if let binary = downloadURLData {
            self.imageData = binary
        }
        // 其次 base64 解码
        if self.imageData == nil, let b64 = item.b64Json {
            self.imageData = Data(base64Encoded: b64)
        }
        self.imageURL = item.url
        self.revisedPrompt = item.revisedPrompt
    }

    /// 直接构造（Mock 或手动）
    init(imageData: Data? = nil, imageURL: String? = nil, revisedPrompt: String? = nil) {
        self.imageData = imageData
        self.imageURL = imageURL
        self.revisedPrompt = revisedPrompt
    }
}
