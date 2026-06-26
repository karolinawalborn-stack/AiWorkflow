import Foundation

// MARK: - 分类错误（UI 可据此显示不同提示）

enum NetworkError: LocalizedError, Sendable {
    case invalidURL(String)
    case connectionFailed(Error)
    case timeout
    case httpError(statusCode: Int, message: String?, url: String?)
    case noData
    case decodingFailed(Error, rawData: Data?)
    case missingAPIKey
    case missingBaseURL
    case unknown(Error)

    /// 错误大类（UI 显示用）
    var category: String {
        switch self {
        case .invalidURL:        return "URL 无效"
        case .connectionFailed:  return "连接失败"
        case .timeout:           return "请求超时"
        case .httpError(let c, _, _):
            if c >= 500 { return "服务器错误(\(c))" }
            if c >= 400 { return "请求被拒(\(c))" }
            return "HTTP \(c)"
        case .noData:            return "无返回数据"
        case .decodingFailed:    return "数据解析失败"
        case .missingAPIKey:     return "API Key 未配置"
        case .missingBaseURL:    return "API URL 未配置"
        case .unknown:           return "未知错误"
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidURL(let u):
            return "URL 格式错误：\(u)"
        case .connectionFailed(let e):
            let ns = e as NSError
            if ns.domain == NSURLErrorDomain {
                if ns.code == NSURLErrorNotConnectedToInternet {
                    return "网络未连接，请检查网络"
                }
                if ns.code == NSURLErrorSecureConnectionFailed {
                    return "安全连接失败，可能是证书问题或 ATS 拦截"
                }
                if ns.code == NSURLErrorCannotConnectToHost {
                    return "无法连接到服务器（域名解析或端口问题）"
                }
            }
            return "连接失败：\(e.localizedDescription)"
        case .timeout:
            return "请求超时，服务器响应过慢，建议重试或检查网络"
        case .httpError(let c, let m, let url):
            var msg = "HTTP \(c)"
            if let detail = m { msg += "：\(detail.prefix(200))" }
            if let u = url { msg += "\nURL: \(u)" }
            return msg
        case .noData:
            return "服务器未返回数据"
        case .decodingFailed(let e, let raw):
            var msg = "数据解析失败：\(e.localizedDescription)"
            if let d = raw, let s = String(data: d, encoding: .utf8) {
                msg += "\n原始数据: \(s.prefix(300))"
            }
            return msg
        case .missingAPIKey:
            return "请先在设置中配置 API Key"
        case .missingBaseURL:
            return "请先在设置中配置 API Base URL"
        case .unknown(let e):
            return "\(e.localizedDescription)"
        }
    }
}

// MARK: - 工厂方法（从 NSError 推断分类）

extension NetworkError {
    static func classify(_ error: Error, url: String? = nil) -> NetworkError {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorTimedOut:
                return .timeout
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorCannotFindHost,
                 NSURLErrorDNSLookupFailed:
                return .connectionFailed(error)
            case NSURLErrorSecureConnectionFailed,
                 NSURLErrorServerCertificateUntrusted,
                 NSURLErrorServerCertificateHasBadDate,
                 NSURLErrorServerCertificateNotYetValid,
                 NSURLErrorClientCertificateRejected:
                return .connectionFailed(error)  // 证书/ATS 问题
            default:
                return .unknown(error)
            }
        }
        if (error as? NetworkError) != nil { return error as! NetworkError }
        return .unknown(error)
    }
}
