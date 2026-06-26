import Foundation

// ═══════════════════════════════════════════════════════
//  AI 文本服务协议（ViewModel 层依赖的唯一接口）
// ═══════════════════════════════════════════════════════
//
// ViewModel 只调用此协议，不关心底层是内部工具站还是别的。
// 返回原始文本，由 ViewModel 自行解析为业务模型。
// ═══════════════════════════════════════════════════════

protocol AITextServiceProtocol: Sendable {
    /// 发送文本生成请求
    /// - Parameters:
    ///   - systemPrompt: 系统提示词
    ///   - userMessage: 用户消息
    ///   - temperature: 温度 (0~2)
    /// - Returns: 模型回复的原始文本
    func chatCompletion(
        systemPrompt: String,
        userMessage: String,
        temperature: Double
    ) async throws -> String
}
