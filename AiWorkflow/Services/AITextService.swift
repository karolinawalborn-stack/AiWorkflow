import Foundation

final class AITextService: AITextServiceProtocol {
    private let httpClient: HTTPClient
    private let config: AIProviderConfig

    init(httpClient: HTTPClient, config: AIProviderConfig) {
        self.httpClient = httpClient
        self.config = config
    }

    func chatCompletion(systemPrompt: String, userMessage: String, temperature: Double) async throws -> String {
        let body = ChatCompletionRequestDTO(
            model: config.textModel,
            messages: [
                MessageDTO(role: "system", content: systemPrompt),
                MessageDTO(role: "user", content: userMessage),
            ],
            temperature: temperature,
            maxTokens: nil
        )
        let bodyData = try JSONEncoder().encode(body)
        let request = APIRequest(
            method: .post,
            url: config.url(for: "/v1/chat/completions"),
            headers: config.authHeaders,
            body: bodyData,
            timeout: config.timeout
        )
        let response: ChatCompletionResponseDTO = try await httpClient.send(request)
        guard let content = response.choices.first?.message.content else { throw NetworkError.noData }
        return content
    }
}
