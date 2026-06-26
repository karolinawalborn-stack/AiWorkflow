import Foundation

// ═══════════════════════════════════════════════════════
//  AI 图片生成服务协议（ViewModel 层依赖的唯一接口）
// ═══════════════════════════════════════════════════════
//
// ViewModel 只调用此协议，返回统一 ImageGenerationResult，
// 不关心底层是 URL 还是 base64。
// ═══════════════════════════════════════════════════════

protocol AIImageServiceProtocol: Sendable {
    /// 生成图片
    /// - Parameters:
    ///   - prompt: 生图提示词
    ///   - size: 尺寸，如 "1024x1792"
    ///   - n: 生成数量
    /// - Returns: ImageGenerationResult 数组（统一格式）
    func generateImage(
        prompt: String,
        size: String,
        n: Int
    ) async throws -> [ImageGenerationResult]
}
