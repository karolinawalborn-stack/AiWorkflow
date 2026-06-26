import Foundation

// ═══════════════════════════════════════════════════════
//  图片生成适配器（适配 /v1/media/generate 接口）
// ═══════════════════════════════════════════════════════
//
//  职责：
//  1. 接收 AIImageServiceProtocol 调用
//  2. 使用 config.imageURLString 构建最终 URL
//  3. 使用 JSONSerialization 构建灵活请求体
//  4. 兼容多种返回格式（url / base64 / 自定义字段）
//  5. 统一输出 ImageGenerationResult
//
//  如果接口格式变了，只改这个文件。
// ═══════════════════════════════════════════════════════

final class InternalToolStationImageAdapter: AIImageServiceProtocol {
    private let httpClient: HTTPClient
    private let config: AIProviderConfig

    init(httpClient: HTTPClient, config: AIProviderConfig) {
        self.httpClient = httpClient
        self.config = config
    }

    func generateImage(
        prompt: String,
        size: String,
        n: Int
    ) async throws -> [ImageGenerationResult] {
        let imageURL = config.imageURLString

        print("""
        🌐 [ImageAdapter] ===== generateImage() =====
           endpoint: POST \(imageURL)
           model: \(config.imageModelName)
           prompt: \(prompt.prefix(200))
           size: \(size)  n: \(n)
        """)

        guard !config.imageModelName.isEmpty else {
            print("🌐 ❌ imageModelName 为空!")
            throw NetworkError.missingBaseURL
        }

        guard !imageURL.isEmpty else {
            print("🌐 ❌ imageURL 为空!")
            throw NetworkError.invalidURL("图片接口 URL 未配置")
        }

        // ── 构建请求体（可扩展字典） ──
        var bodyDict: [String: Any] = [
            "model": config.imageModelName,
            "prompt": prompt,
            "n": n,
            "size": size,
        ]
        // 某些接口需要 response_format 字段
        bodyDict["response_format"] = "b64_json"

        let bodyData = try JSONSerialization.data(withJSONObject: bodyDict, options: [])
        print("""
        🌐 [ImageAdapter] 请求体 (\(bodyData.count) bytes):
           \(String(data: bodyData, encoding: .utf8)?.prefix(500) ?? "N/A")
        """)

        let request = APIRequest(
            method: .post,
            url: imageURL,
            headers: config.authHeaders,
            body: bodyData,
            timeout: config.timeout
        )

        print("""
        🌐 [ImageAdapter] 即将发送请求:
           URL: \(request.url)
           Method: \(request.method.rawValue)
           Auth: \(request.headers["Authorization"] != nil ? "✅" : "❌ 无 Token")
           Timeout: \(config.timeout)s
        """)

        // ── 发请求 ──
        let rawData = try await httpClient.sendRaw(request)

        print("🌐 [ImageAdapter] 原始响应大小: \(rawData.count) bytes")
        if let rawStr = String(data: rawData, encoding: .utf8) {
            print("🌐 [ImageAdapter] 原始响应前1000字: \(rawStr.prefix(1000))")
        }

        // ── 灵活解析返回 ──
        let parsed = FlexibleImageResponseParser.parse(from: rawData)
        print("""
        🌐 [ImageAdapter] 解析结果:
           url=\(parsed.url ?? "nil")
           hasBase64=\(parsed.base64 != nil)
           revisedPrompt=\(parsed.revisedPrompt?.prefix(100) ?? "nil")
        """)

        // 构造 ImageGenerationResult
        var imageData: Data? = nil
        if let b64 = parsed.base64 {
            imageData = Data(base64Encoded: b64)
            print("🌐 [ImageAdapter] base64 解码: \(imageData?.count ?? 0) bytes")
        }
        if imageData == nil, let urlStr = parsed.url, let url = URL(string: urlStr) {
            print("🌐 [ImageAdapter] 开始下载 URL 图片: \(urlStr)")
            if let (data, _) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: config.timeout)) {
                imageData = data
                print("🌐 [ImageAdapter] URL 下载成功: \(data.count) bytes")
            } else {
                print("🌐 [ImageAdapter] URL 下载失败")
            }
        }

        let result = ImageGenerationResult(
            imageData: imageData,
            imageURL: parsed.url,
            revisedPrompt: parsed.revisedPrompt
        )

        print("🌐 [ImageAdapter] 最终结果: imageData=\(result.imageData?.count ?? 0) bytes, imageURL=\(result.imageURL ?? "nil")")

        if imageData == nil {
            print("🌐 [ImageAdapter] ⚠️ 所有解析方式都未获取到图片数据")
        }

        return [result]
    }
}
