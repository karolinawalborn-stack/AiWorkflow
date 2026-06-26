import Foundation

struct ChatCompletionRequestDTO: Encodable, Sendable {
    let model: String
    let messages: [MessageDTO]
    let temperature: Double?
    let maxTokens: Int?
    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
    }
}

struct MessageDTO: Codable, Sendable {
    let role: String
    let content: String
}

struct ChatCompletionResponseDTO: Decodable, Sendable {
    let id: String?
    let choices: [ChoiceDTO]
    let usage: UsageDTO?
}

struct ChoiceDTO: Decodable, Sendable {
    let index: Int
    let message: MessageDTO
    let finishReason: String?
    enum CodingKeys: String, CodingKey {
        case index, message
        case finishReason = "finish_reason"
    }
}

struct UsageDTO: Decodable, Sendable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}
