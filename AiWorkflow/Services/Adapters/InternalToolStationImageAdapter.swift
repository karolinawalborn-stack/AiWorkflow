import Foundation

// ═══════════════════════════════════════════════════════
//  AI领航局-内部工具站 图片生成适配器
// ═══════════════════════════════════════════════════════
//
//  职责：
//  1. 接收 AIImageServiceProtocol 调用
//  2. 构建内部工具站格式的图生请求
//  3. 发送 HTTP 请求
//  4. 兼容 URL / base64 / 二进制 三种返回形式
//  5. 统一输出 ImageGenerationResult
//
//  如果内部工具站的图片接口格式变了，只改这个文件。
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
        // ── 1. 先请求 base64 格式（最通用） ──
        var results = try await requestImages(
            prompt: prompt,
            size: size,
            n: n,
            responseFormat: "b64_json"
        )

        // ── 2. 如果 base64 全部失败，回退到 URL 格式 ──
        if results.allSatisfy({ $0.imageData == nil }) {
            results = try await requestImages(
                prompt: prompt,
                size: size,
                n: n,
                responseFormat: "url"
            )
        }

        return results
    }

    /// 以指定格式请求图片
    private func requestImages(
        prompt: String,
        size: String,
        n: Int,
        responseFormat: String
    ) async throws -> [ImageGenerationResult] {
        let body = InternalToolStationImageRequest(
            model: config.imageModelNameName,
            prompt: prompt,
            n: n,
            size: size,
            responseFormat: responseFormat
        )

        let bodyData = try JSONEncoder().encode(body)

        let request = APIRequest(
            method: .post,
            url: config.url(for: "/v1/images/generations"),
            headers: config.authHeaders,
            body: bodyData,
            timeout: config.timeout
        )

        let response: InternalToolStationImageResponse = try await httpClient.send(request)

        // 如果是 URL 格式，下载每张图片的二进制数据
        if responseFormat == "url" {
            return try await convertURLResults(response.data)
        } else {
            return response.data.map { ImageGenerationResult(from: $0) }
        }
    }

    /// URL 格式：逐个下载图片二进制
    private func convertURLResults(_ items: [InternalImageData]) async throws -> [ImageGenerationResult] {
        var results: [ImageGenerationResult] = []
        for item in items {
            if let urlStr = item.url, let url = URL(string: urlStr) {
                let request = URLRequest(url: url, timeoutInterval: config.timeout)
                if let (data, _) = try? await URLSession.shared.data(for: request) {
                    results.append(ImageGenerationResult(from: item, downloadURLData: data))
                } else {
                    results.append(ImageGenerationResult(from: item))
                }
            } else {
                results.append(ImageGenerationResult(from: item))
            }
        }
        return results
    }
}
