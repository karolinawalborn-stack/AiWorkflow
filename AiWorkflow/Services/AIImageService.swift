import Foundation

final class AIImageService: AIImageServiceProtocol {
    private let httpClient: HTTPClient
    private let config: AIProviderConfig

    init(httpClient: HTTPClient, config: AIProviderConfig) {
        self.httpClient = httpClient
        self.config = config
    }

    func generateImage(prompt: String, size: String, n: Int) async throws -> [GeneratedImageResult] {
        let body = ImageGenerationRequestDTO(
            model: config.imageModel,
            prompt: prompt,
            n: n,
            size: size,
            responseFormat: "b64_json"
        )
        let bodyData = try JSONEncoder().encode(body)
        let request = APIRequest(
            method: .post,
            url: config.url(for: "/v1/images/generations"),
            headers: config.authHeaders,
            body: bodyData,
            timeout: config.timeout
        )
        let response: ImageGenerationResponseDTO = try await httpClient.send(request)
        return response.data.map {
            GeneratedImageResult(data: $0.b64Json.flatMap { Data(base64Encoded: $0) }, url: $0.url, revisedPrompt: $0.revisedPrompt)
        }
    }
}
