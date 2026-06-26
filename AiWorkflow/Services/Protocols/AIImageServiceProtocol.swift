import Foundation

protocol AIImageServiceProtocol: Sendable {
    /// 生成图片（无参考图）
    func generateImage(prompt: String, size: String, n: Int) async throws -> [ImageGenerationResult]

    /// 生成图片（带参考图）
    func generateImage(prompt: String, size: String, n: Int, referenceImageBase64: String?, referenceMode: String) async throws -> [ImageGenerationResult]
}
