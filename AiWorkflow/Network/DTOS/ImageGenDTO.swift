import Foundation

struct ImageGenerationRequestDTO: Encodable, Sendable {
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

struct ImageGenerationResponseDTO: Decodable, Sendable {
    let created: Int?
    let data: [ImageDataDTO]
}

struct ImageDataDTO: Decodable, Sendable {
    let b64Json: String?
    let url: String?
    let revisedPrompt: String?
    enum CodingKeys: String, CodingKey {
        case b64Json = "b64_json"
        case url
        case revisedPrompt = "revised_prompt"
    }
}

struct GeneratedImageResult: Sendable {
    let data: Data?
    let url: String?
    let revisedPrompt: String?
}
