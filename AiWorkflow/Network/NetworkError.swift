import Foundation

enum NetworkError: LocalizedError, Sendable {
    case invalidURL, noData, decodingFailed(Error)
    case httpError(statusCode: Int, message: String?)
    case missingAPIKey, missingBaseURL, unknown(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:       return "无效的 URL"
        case .noData:           return "服务器未返回数据"
        case .decodingFailed(let e): return "数据解析失败：\(e.localizedDescription)"
        case .httpError(let c, let m): return "HTTP \(c)：\(m ?? "未知")"
        case .missingAPIKey:    return "请先配置 API Key"
        case .missingBaseURL:   return "请先配置 API Base URL"
        case .unknown(let e):   return "网络错误：\(e.localizedDescription)"
        }
    }
}
