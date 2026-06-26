import Foundation

enum APIEndpoint: String, Sendable {
    case chatCompletion  = "/v1/chat/completions"
    case imageGeneration = "/v1/images/generations"
}
