import Foundation

final class InternalToolStationImageAdapter: AIImageServiceProtocol {
    private let httpClient: HTTPClient
    private let config: AIProviderConfig

    init(httpClient: HTTPClient, config: AIProviderConfig) {
        self.httpClient = httpClient
        self.config = config
    }

    func generateImage(prompt: String, size: String, n: Int) async throws -> [ImageGenerationResult] {
        return try await sendImageRequest(prompt: prompt, size: size, n: n, referenceImageBase64: nil, referenceMode: "disabled")
    }

    func generateImage(prompt: String, size: String, n: Int, referenceImageBase64: String?, referenceMode: String) async throws -> [ImageGenerationResult] {
        return try await sendImageRequest(prompt: prompt, size: size, n: n, referenceImageBase64: referenceImageBase64, referenceMode: referenceMode)
    }

    private func sendImageRequest(prompt: String, size: String, n: Int, referenceImageBase64: String?, referenceMode: String) async throws -> [ImageGenerationResult] {
        let imageURL = config.imageURLString
        var bodyDict: [String: Any] = [
            config.imagePromptFieldName: prompt,
            "model": config.imageModelName,
            "n": n,
            "size": size,
        ]

        // 参考图
        if let b64 = referenceImageBase64, !b64.isEmpty, referenceMode != "disabled" {
            switch referenceMode {
            case "base64", "imageURL", "multipartUpload":
                bodyDict[config.referenceImageFieldName] = b64
            case "promptOnlyFallback":
                let styleHint = "请严格参考上传参考图的人物造型、线条风格、留白边框、双格排版、角色一致性与整体色调"
                bodyDict[config.imagePromptFieldName] = prompt + "\n\n[风格参考要求] " + styleHint
            default:
                bodyDict[config.imagePromptFieldName] = prompt + "\n\n[风格参考要求] 请参考上传的风格参考图"
            }
        }

        let bodyData = try JSONSerialization.data(withJSONObject: bodyDict, options: [])
        let request = APIRequest(method: .post, url: imageURL, headers: config.authHeaders, body: bodyData, timeout: config.timeout)

        print("""
        🌐 [Adapter] ===== 发送图片请求 =====
           URL: POST \(imageURL)
           Body 字段: \(bodyDict.keys.joined(separator: ", "))
           Body 大小: \(bodyData.count) bytes
        """)

        let httpResp = try await httpClient.sendRaw(request)

        // ── 按 Content-Type 分支处理 ──
        return try await processResponse(httpResp, prompt: prompt)
    }

    /// 根据 Content-Type 分支处理响应
    private func processResponse(_ resp: HTTPResponse, prompt: String) async throws -> [ImageGenerationResult] {
        let ct = resp.contentType.lowercased()
        let data = resp.data
        let rawText = String(data: data, encoding: .utf8)
        let statusCode = resp.statusCode

        print("""
        🌐 [Adapter] processResponse:
           Content-Type: \(ct)
           Status: HTTP \(statusCode)
           Body 长度: \(data.count) bytes
        """)

        // ── 1. image/* → 直接作为图片二进制 ──
        if ct.hasPrefix("image/") {
            print("🌐 [Adapter] ✅ 图片二进制响应 (\(ct))")
            print("🌐 [Adapter]    大小: \(data.count) bytes, 直接保存")
            let summary = "[二进制图片] Content-Type: \(ct), 大小: \(data.count) bytes"
            return [ImageGenerationResult(
                imageData: data,
                rawResponseText: summary,
                statusCode: statusCode,
                contentType: ct
            )]
        }

        // ── 2. application/json → JSON 解析 ──
        if ct.contains("json") {
            print("🌐 [Adapter] ✅ JSON 响应, 长度=\(data.count)")
            let fullJSON = rawText ?? "\(data.count) bytes (non-UTF8)"
            print("🌐 [Adapter] JSON: \(fullJSON.prefix(2000))")

            // 尝试多种解析
            let parsed = FlexibleImageResponseParser.parse(from: data)
            print("""
            🌐 [Adapter] JSON 解析结果:
               url=\(parsed.url ?? "nil")
               base64=\(parsed.base64 != nil ? "长度\(parsed.base64!.count)" : "nil")
               taskID=\(parsed.taskID ?? "nil")
            """)

            // 检查是否为异步任务
            if let taskID = parsed.taskID {
                let efsIds = Self.extractEFSIds(from: fullJSON)
                print("🌐 [Adapter] ⏳ taskID=\(taskID) efsIds=\(efsIds)")
                return [ImageGenerationResult(
                    imageData: nil,
                    revisedPrompt: parsed.revisedPrompt,
                    rawResponseText: fullJSON,
                    statusCode: statusCode,
                    contentType: ct,
                    taskID: taskID,
                    efsIds: efsIds
                )]
            }

            // 正常解析：获取图片数据
            var imageData: Data? = nil
            if let b64 = parsed.base64 {
                imageData = Data(base64Encoded: b64)
                print("🌐 [Adapter] base64 解码: \(imageData?.count ?? 0) bytes")
            }
            if imageData == nil, let urlStr = parsed.url, let url = URL(string: urlStr) {
                print("🌐 [Adapter] 下载 URL: \(urlStr)")
                if let (d, _) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: config.timeout)) {
                    imageData = d
                    print("🌐 [Adapter] URL 下载成功: \(d.count) bytes")
                } else {
                    print("🌐 [Adapter] URL 下载失败")
                }
            }

            return [ImageGenerationResult(
                imageData: imageData,
                imageURL: parsed.url,
                revisedPrompt: parsed.revisedPrompt,
                rawResponseText: fullJSON,
                statusCode: statusCode,
                contentType: ct
            )]
        }

        // ── 3. text/plain 或 text/html → 纯文本 ──
        if ct.hasPrefix("text/") {
            let text = rawText ?? "\(data.count) bytes (non-UTF8)"
            print("🌐 [Adapter] ✅ 文本响应: \(text.prefix(500))")

            // 尝试作为 URL
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"), let url = URL(string: trimmed) {
                print("🌐 [Adapter] 文本看起来是 URL, 开始下载...")
                if let (d, _) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: config.timeout)) {
                    return [ImageGenerationResult(
                        imageData: d,
                        rawResponseText: text,
                        statusCode: statusCode,
                        contentType: ct
                    )]
                }
            }

            // 纯文本 → 保留全文作为调试信息
            return [ImageGenerationResult(
                rawResponseText: text,
                statusCode: statusCode,
                contentType: ct
            )]
        }

        // ── 4. 未知类型 ──
        let summaryText = rawText ?? "[二进制/未知格式] Content-Type: \(ct), 大小: \(data.count) bytes"
        print("🌐 [Adapter] ❓ 未知响应类型 ct=\(ct), 前200: \(String(rawText?.prefix(200) ?? "N/A"))")
        return [ImageGenerationResult(
            rawResponseText: summaryText,
            statusCode: statusCode,
            contentType: ct
        )]
    }

    /// 从 JSON 响应中提取 efsIds
    private static func extractEFSIds(from jsonStr: String) -> [String] {
        guard let data = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let d = json["data"] as? [String: Any],
              let efs = d["efsIds"] as? [String] else { return [] }
        return efs
    }
}
