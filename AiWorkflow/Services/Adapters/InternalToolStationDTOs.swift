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

/// 灵活图片响应解析器——递归搜索所有可能的图片字段
///
/// 支持的格式（自动递归搜索）：
///   - 数组路径: data[] / images[] / results[] / output[] / items[]
///   - URL 字段: url / imageUrl / image_url / imageURL / link / download_url / src / source
///   - base64 字段: b64_json / base64 / image_base64 / imageData / data / content
///   - 嵌套对象: data.url / data.imageUrl / result.link 等
///   - 异步任务: task_id / taskId / id + status (queued/processing/pending)
///   - 递归兜底: 遍历整个 JSON 树查找第一个像 URL 或 base64 的字符串
enum FlexibleImageResponseParser {
    /// 返回值扩展了 taskID，用于异步任务型接口
    static func parse(from data: Data) -> (url: String?, base64: String?, revisedPrompt: String?, taskID: String?) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                print("📦 [FlexibleParser] 响应非 JSON")
                if text.hasPrefix("http://") || text.hasPrefix("https://") { return (text, nil, nil, nil) }
                if text.count > 100 { return (nil, text, nil, nil) }
            }
            return (nil, nil, nil, nil)
        }

        print("📦 [FlexibleParser] JSON keys: \(json.keys.joined(separator: ", "))")
        let taskID = Self.extractTaskID(json)
        if taskID != nil { print("📦 [FlexibleParser] ⏳ taskID=\(taskID!)") }

        for arrKey in ["data","images","results","output","items","image","imgs"] {
            if let arr = json[arrKey] as? [[String: Any]], let first = arr.first {
                if let r = extractFromDict(first) { return (r.url, r.base64, r.revisedPrompt, taskID) }
            }
        }
        for objKey in ["data","result","image","output","response"] {
            if let obj = json[objKey] as? [String: Any], let r = extractFromDict(obj) { return (r.url, r.base64, r.revisedPrompt, taskID) }
        }
        if let r = extractFromDict(json) { return (r.url, r.base64, r.revisedPrompt, taskID) }
        if let r = recursiveSearch(json, depth: 0, maxDepth: 5) { return (r.url, r.base64, r.revisedPrompt, taskID) }

        if let d = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted,.sortedKeys]),
           let s = String(data: d, encoding: .utf8) { print(s) }
        return (nil, nil, nil, taskID)
    }

    private static func extractTaskID(_ json: [String: Any]) -> String? {
        for key in ["task_id","taskId","id","request_id","requestId"] {
            if let val = json[key] as? String, !val.isEmpty { return val }
            if let val = json[key] as? Int { return "\(val)" }
        }
        if let data = json["data"] as? [String: Any] {
            for key in ["task_id","taskId","id","request_id"] {
                if let val = data[key] as? String, !val.isEmpty { return val }
                if let val = data[key] as? Int { return "\(val)" }
            }
        }
        return nil
    }

    /// 从字典中提取图片字段（检查多种 key 名）
    private static func extractFromDict(_ dict: [String: Any]) -> (url: String?, base64: String?, revisedPrompt: String?)? {
        let urlKeys = ["url", "imageUrl", "image_url", "imageURL", "link", "download_url", "src", "source", "image_url"]
        let b64Keys = ["b64_json", "base64", "image_base64", "imageData", "image_data", "data", "content", "file_base64"]

        if let url = string(from: dict, keys: urlKeys) {
            print("📦 [FlexibleParser] ✅ 提取到 URL: \(url.prefix(80))")
            return (url, nil, dict["revised_prompt"] as? String)
        }
        for key in b64Keys {
            if let val = dict[key] as? String, !val.isEmpty {
                print("📦 [FlexibleParser] ✅ 提取到 base64(\(key)): 长度=\(val.count)")
                return (nil, val, dict["revised_prompt"] as? String)
            }
        }
        return nil
    }

    /// 递归搜索整个 JSON 树，查找像 URL 或 base64 的字符串
    private static func recursiveSearch(_ value: Any, depth: Int, maxDepth: Int) -> (url: String?, base64: String?, revisedPrompt: String?, taskID: String?)? {
        if depth > maxDepth { return nil }
        let indent = String(repeating: "  ", count: depth)

        if let dict = value as? [String: Any] {
            // 先检查这个 dict 本身
            if let result = extractFromDict(dict) { return (result.url, result.base64, result.revisedPrompt, nil) }
            // 再递归子字段
            for (key, val) in dict {
                if key == "revised_prompt" { continue }
                print("\(indent)🔍 [递归] 进入 \(key)")
                if let result = recursiveSearch(val, depth: depth + 1, maxDepth: maxDepth) {
                    return result
                }
            }
        }

        if let arr = value as? [Any] {
            for (i, item) in arr.enumerated() {
                if i > 2 { break } // 最多查前 3 个
                print("\(indent)🔍 [递归] 进入 [\(i)]")
                if let result = recursiveSearch(item, depth: depth + 1, maxDepth: maxDepth) {
                    return result
                }
            }
        }

        // 字符串类型：检查是否直接就是 URL 或 base64
        if let str = value as? String, str.count > 20 {
            if str.hasPrefix("http://") || str.hasPrefix("https://") || str.hasPrefix("data:image") {
                print("\(indent)📦 [递归] ✅ 找到内联 URL: \(str.prefix(80))")
                return (str, nil, nil, nil)
            }
            if !str.contains(" ") && str.count > 100 && str.rangeOfCharacter(from: .whitespacesAndNewlines) == nil {
                print("\(indent)📦 [递归] ✅ 找到疑似 base64: 长度=\(str.count)")
                return (nil, str, nil, nil)
            }
        }

        return nil
    }

    private static func string(from dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let val = dict[key] as? String, !val.isEmpty { return val }
        }
        return nil
    }
}

// MARK: - 图片结果（统一格式，兼容 URL / base64 / 二进制）

/// 图片生成结果——适配层统一输出格式
struct ImageGenerationResult: Sendable {
    /// 图片二进制数据
    public private(set) var imageData: Data?
    /// 图片 URL
    public private(set) var imageURL: String?
    /// API 优化后的提示词
    public private(set) var revisedPrompt: String?
    /// 原始 HTTP 响应的文本表示（用于调试）
    public private(set) var rawResponseText: String?
    /// HTTP 状态码
    public private(set) var statusCode: Int?
    /// Content-Type
    public private(set) var contentType: String?
    /// 异步任务 ID（如果接口返回任务模式）
    public private(set) var taskID: String?
    public private(set) var efsIds: [String]

    init(imageData: Data? = nil, imageURL: String? = nil, revisedPrompt: String? = nil, rawResponseText: String? = nil, statusCode: Int? = nil, contentType: String? = nil, taskID: String? = nil, efsIds: [String] = []) {
        self.imageData = imageData
        self.imageURL = imageURL
        self.revisedPrompt = revisedPrompt
        self.rawResponseText = rawResponseText
        self.statusCode = statusCode
        self.contentType = contentType
        self.taskID = taskID
        self.efsIds = efsIds
    }
}
