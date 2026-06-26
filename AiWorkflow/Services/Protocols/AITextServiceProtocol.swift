import Foundation

protocol AITextServiceProtocol: Sendable {
    func chatCompletion(
        systemPrompt: String,
        userMessage: String,
        temperature: Double
    ) async throws -> String
}
