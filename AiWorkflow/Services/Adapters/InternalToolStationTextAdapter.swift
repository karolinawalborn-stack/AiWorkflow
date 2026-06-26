import Foundation

// ═══════════════════════════════════════════════════════
//  AI领航局-内部工具站 文本生成适配器
// ═══════════════════════════════════════════════════════
//
//  职责：
//  1. 接收 AITextServiceProtocol 调用
//  2. 构建内部工具站格式的请求体
//  3. 发送 HTTP 请求
//  4. 解析内部工具站格式的响应
//  5. 返回纯文本给 ViewModel
//
//  如果内部工具站的 API 格式变了，只改这个文件。
// ═══════════════════════════════════════════════════════

final class InternalToolStationTextAdapter: AITextServiceProtocol {
    private let httpClient: HTTPClient
    private let config: AIProviderConfig

    init(httpClient: HTTPClient, config: AIProviderConfig) {
        self.httpClient = httpClient
        self.config = config
    }

    func chatCompletion(
        systemPrompt: String,
        userMessage: String,
        temperature: Double
    ) async throws -> String {
        // ── 1. 构建内部工具站格式的请求 ──
        let body = InternalToolStationTextRequest(
            model: config.textModelName,
            messages: [
                InternalTextMessage(role: "system", content: systemPrompt),
                InternalTextMessage(role: "user", content: userMessage),
            ],
            temperature: temperature
        )

        let bodyData = try JSONEncoder().encode(body)

        let request = APIRequest(
            method: .post,
            url: config.url(for: "/v1/chat/completions"),
            headers: config.authHeaders,
            body: bodyData,
            timeout: config.timeout
        )

        // ── 2. 发送并解析 ──
        let response: InternalToolStationTextResponse = try await httpClient.send(request)

        // ── 3. 校验并返回文本 ──
        guard let content = response.choices.first?.message.content else {
            throw NetworkError.noData
        }
        return content
    }
}
