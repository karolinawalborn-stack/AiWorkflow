import Foundation

// ═══════════════════════════════════════════════════════
//  图片生成适配器（适配 /v1/media/generate + 参考图）
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
        // 走无参考图模式
        let bodyDict = buildRequestBody(prompt: prompt, size: size, n: n, referenceImageData: nil)
        return try await sendImageRequest(bodyDict: bodyDict)
    }

    /// 带参考图生成
    func generateImage(
        prompt: String,
        size: String,
        n: Int,
        referenceImageBase64: String?,
        referenceMode: String
    ) async throws -> [ImageGenerationResult] {
        let bodyDict = buildRequestBody(
            prompt: prompt,
            size: size,
            n: n,
            referenceImageData: (referenceImageBase64, referenceMode)
        )
        return try await sendImageRequest(bodyDict: bodyDict)
    }

    // MARK: - 请求体构造

    private func buildRequestBody(
        prompt: String,
        size: String,
        n: Int,
        referenceImageData: (base64: String?, mode: String)?
    ) -> [String: Any] {
        let refB64 = referenceImageData?.base64
        let refMode = referenceImageData?.mode ?? "promptOnlyFallback"

        var body: [String: Any] = [
            config.imagePromptFieldName: prompt,
            "model": config.imageModelName,
            "n": n,
            "size": size,
        ]

        // 处理参考图
        if let b64 = refB64, !b64.isEmpty, refMode != "disabled" {
            switch refMode {
            case "base64":
                // 直接把 base64 嵌入请求体
                body[config.referenceImageFieldName] = b64
                print("🌐 [Adapter] 参考图模式=base64, 字段=\(config.referenceImageFieldName), base64长度=\(b64.count)")

            case "imageURL":
                // 如果是 URL 模式但传了 base64，先存着等外部处理
                print("🌐 [Adapter] 参考图模式=imageURL, 需要由外部先上传获取 URL")
                body[config.referenceImageFieldName] = b64

            case "multipartUpload":
                print("🌐 [Adapter] 参考图模式=multipartUpload, 当前以 base64 嵌入")
                body[config.referenceImageFieldName] = b64

            case "promptOnlyFallback":
                // 把参考图描述拼进 prompt（默认）
                let styleHint = "请严格参考上传参考图的人物造型、线条风格、留白边框、双格排版、角色一致性与整体色调"
                body[config.imagePromptFieldName] = prompt + "\n\n[风格参考要求] " + styleHint
                print("🌐 [Adapter] 参考图模式=promptOnlyFallback, 已拼接风格描述到 prompt")

            default:
                print("🌐 [Adapter] 参考图模式=\(refMode), 当前以 promptOnlyFallback 降级")
                let styleHint = "请严格参考上传参考图的人物造型、线条风格、留白边框、双格排版、角色一致性与整体色调"
                body[config.imagePromptFieldName] = prompt + "\n\n[风格参考要求] " + styleHint
            }
        }

        return body
    }

    // MARK: - 发送请求

    private func sendImageRequest(bodyDict: [String: Any]) async throws -> [ImageGenerationResult] {
        let imageURL = config.imageURLString
        let bodyData = try JSONSerialization.data(withJSONObject: bodyDict, options: [])

        print("""
        🌐 [Adapter] ===== 发送图片请求 =====
           URL: POST \(imageURL)
           Model: \(config.imageModelName)
           请求体字段: \(bodyDict.keys.joined(separator: ", "))
           请求体大小: \(bodyData.count) bytes
        """)

        guard !imageURL.isEmpty else {
            throw NetworkError.invalidURL("图片接口 URL 未配置")
        }

        let request = APIRequest(
            method: .post,
            url: imageURL,
            headers: config.authHeaders,
            body: bodyData,
            timeout: config.timeout
        )

        print("""
        🌐 [Adapter] 请求详情:
           URL: \(request.url)
           Method: \(request.method.rawValue)
           Auth: \(request.headers["Authorization"] != nil ? "✅" : "❌")
        """)

        let rawData = try await httpClient.sendRaw(request)
        print("🌐 [Adapter] 原始响应: \(rawData.count) bytes")

        if let rawStr = String(data: rawData, encoding: .utf8) {
            print("🌐 [Adapter] ⬇️⬇️⬇️ 原始响应全文 ⬇️⬇️⬇️")
            print(rawStr)
            print("🌐 [Adapter] ⬆️⬆️⬆️ 原始响应结束 ⬆️⬆️⬆️")
        }

        // 解析
        let parsed = FlexibleImageResponseParser.parse(from: rawData)
        print("""
        🌐 [Adapter] 解析结果:
           url=\(parsed.url ?? "nil")
           base64=\(parsed.base64 != nil ? "\(parsed.base64!.prefix(30))..." : "nil")
        """)

        // 获取图片数据
        var imageData: Data? = nil
        if let b64 = parsed.base64 {
            imageData = Data(base64Encoded: b64)
            print("🌐 [Adapter] base64 解码: \(imageData?.count ?? 0) bytes")
        }
        if imageData == nil, let urlStr = parsed.url, let url = URL(string: urlStr) {
            print("🌐 [Adapter] 开始下载 URL: \(urlStr)")
            if let (data, _) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: config.timeout)) {
                imageData = data
                print("🌐 [Adapter] URL 下载成功: \(data.count) bytes")
            } else {
                print("🌐 [Adapter] URL 下载失败")
            }
        }

        let result = ImageGenerationResult(
            imageData: imageData,
            imageURL: parsed.url,
            revisedPrompt: parsed.revisedPrompt
        )

        if imageData == nil {
            print("🌐 [Adapter] ❌ 所有解析方式均未获取到图片数据")
        }

        return [result]
    }
}
