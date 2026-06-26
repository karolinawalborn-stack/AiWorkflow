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

/// 图片生成请求体（OpenAI 兼容格式，用于 /v1/images/generations）
struct InternalToolStationImageRequest: Encodable, Sendable {
    let model: String
    let prompt: String
    let n: Int
    let size: String
    let responseFormat: String

    enum CodingKeys: String, CodingKey {
        case model, prompt, n, size
        case responseFormat = "response_format"
    }
}

/// 灵活图片请求体（用于新接口 /v1/media/generate，字典构造）
/// 自动包含 prompt、model，其他字段可扩展
struct FlexibleImageRequestBody: Encodable, Sendable {
    let model: String
    let prompt: String
    let n: Int
    let size: String
    /// 额外字段
    let extra: [String: String]

    init(model: String, prompt: String, n: Int, size: String, extra: [String: String] = [:]) {
        self.model = model
        self.prompt = prompt
        self.n = n
        self.size = size
        self.extra = extra
    }

    enum CodingKeys: String, CodingKey {
        case model, prompt, n, size
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(n, forKey: .n)
        try container.encode(size, forKey: .size)
        // 额外字段直接写入 JSON 根层
        for (key, value) in extra {
            let keyCoding = ExtraCodingKey(stringValue: key)
            var extraContainer = encoder.container(keyedBy: ExtraCodingKey.self)
            try extraContainer.encode(value, forKey: keyCoding)
        }
    }

    struct ExtraCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}

/// 图片生成响应（OpenAI 兼容格式）
struct InternalToolStationImageResponse: Decodable, Sendable {
    let data: [InternalImageData]
}

struct InternalImageData: Decodable, Sendable {
    let url: String?
    let b64Json: String?
    let revisedPrompt: String?

    enum CodingKeys: String, CodingKey {
        case url
        case b64Json = "b64_json"
        case revisedPrompt = "revised_prompt"
    }
}

/// 灵活图片响应解析器——兼容多种字段路径
enum FlexibleImageResponseParser {
    /// 尝试从原始 JSON Data 中提取图片 URL 或 base64
    /// 支持的字段路径（按优先级）：
    ///   - data[0].url / data[0].b64_json     (OpenAI)
    ///   - data[0].imageUrl / data[0].imageURL
    ///   - url / imageUrl / imageURL          (顶层字段)
    ///   - data.url / data.imageUrl           (data 对象)
    ///   - base64 / data.base64
    static func parse(from data: Data) -> (url: String?, base64: String?, revisedPrompt: String?) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, nil, nil)
        }

        print("📦 [FlexibleParser] 原始 JSON keys: \(json.keys.joined(separator: ", "))")

        // 优先: data 数组
        if let dataArray = json["data"] as? [[String: Any]], let first = dataArray.first {
            print("📦 [FlexibleParser] data[0] keys: \(first.keys.joined(separator: ", "))")
            if let url = string(from: first, keys: ["url", "imageUrl", "imageURL"]) {
                print("📦 [FlexibleParser] 从 data[0].\(fieldName(from: first, keys: ["url", "imageUrl", "imageURL"])) 获取到 URL")
                return (url, nil, first["revised_prompt"] as? String)
            }
            if let b64 = string(from: first, keys: ["b64_json", "base64", "imageBase64"]) {
                print("📦 [FlexibleParser] 从 data[0] 获取到 base64, 长度=\(b64.count)")
                return (nil, b64, first["revised_prompt"] as? String)
            }
        }

        // 次优: data 是对象
        if let dataObj = json["data"] as? [String: Any] {
            print("📦 [FlexibleParser] data(对象) keys: \(dataObj.keys.joined(separator: ", "))")
            if let url = string(from: dataObj, keys: ["url", "imageUrl", "imageURL"]) {
                return (url, nil, dataObj["revised_prompt"] as? String)
            }
            if let b64 = string(from: dataObj, keys: ["b64_json", "base64", "imageBase64"]) {
                return (nil, b64, dataObj["revised_prompt"] as? String)
            }
        }

        // 最后: 顶层字段
        if let url = string(from: json, keys: ["url", "imageUrl", "imageURL"]) {
            print("📦 [FlexibleParser] 从顶层提取到 URL")
            return (url, nil, json["revised_prompt"] as? String)
        }
        if let b64 = string(from: json, keys: ["b64_json", "base64", "imageBase64"]) {
            print("📦 [FlexibleParser] 从顶层提取到 base64")
            return (nil, b64, json["revised_prompt"] as? String)
        }

        print("📦 [FlexibleParser] ❌ 无法从响应中提取图片数据")
        if let preview = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
           let str = String(data: preview, encoding: .utf8) {
            print("📦 [FlexibleParser] 完整响应:\n\(str.prefix(1000))")
        }
        return (nil, nil, nil)
    }

    private static func string(from dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let val = dict[key] as? String, !val.isEmpty { return val }
        }
        return nil
    }

    private static func fieldName(from dict: [String: Any], keys: [String]) -> String {
        for key in keys {
            if dict[key] as? String != nil { return key }
        }
        return keys.first ?? "?"
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
