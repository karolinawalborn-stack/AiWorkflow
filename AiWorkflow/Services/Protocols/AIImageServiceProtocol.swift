import Foundation

protocol AIImageServiceProtocol: Sendable {
    func generateImage(
        prompt: String,
        size: String,
        n: Int
    ) async throws -> [GeneratedImageResult]
}
