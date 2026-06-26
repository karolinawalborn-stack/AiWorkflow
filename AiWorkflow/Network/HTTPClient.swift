import Foundation

enum HTTPMethod: String, Sendable { case get = "GET", post = "POST" }

struct APIRequest: Sendable {
    let method: HTTPMethod
    let url: String
    let headers: [String: String]
    let body: Data?
    let timeout: TimeInterval
}

/// HTTP 响应（含元数据）
struct HTTPResponse: Sendable {
    let data: Data
    let statusCode: Int
    let contentType: String
    let headers: [String: String]
}

/// HTTP 客户端
final class HTTPClient: @unchecked Sendable {
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) { self.session = session }

    func send<T: Decodable>(_ request: APIRequest) async throws -> T {
        let httpResp = try await sendRaw(request)
        do { return try decoder.decode(T.self, from: httpResp.data) }
        catch {
            throw NetworkError.decodingFailed(error, rawData: httpResp.data)
        }
    }

    /// 发送请求，返回完整响应（data + statusCode + contentType + headers）
    @discardableResult
    func sendRaw(_ request: APIRequest) async throws -> HTTPResponse {
        guard let url = URL(string: request.url) else {
            throw NetworkError.invalidURL(request.url)
        }

        var req = URLRequest(url: url)
        req.httpMethod = request.method.rawValue
        req.allHTTPHeaderFields = request.headers
        req.httpBody = request.body
        req.timeoutInterval = request.timeout

        let startTime = Date()
        let requestId = UUID().uuidString.prefix(8)
        print("🌐 [\(requestId)] >>> \(request.method.rawValue) \(request.url)")
        if let body = request.body, let bodyStr = String(data: body, encoding: .utf8) {
            print("🌐 [\(requestId)] Body: \(bodyStr.prefix(300))")
        }

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: req)
        } catch {
            let elapsed = Date().timeIntervalSince(startTime)
            let nsError = error as NSError
            print("🌐 [\(requestId)] <<< FAIL after \(String(format: "%.1f", elapsed))s")
            print("🌐 [\(requestId)] Error domain=\(nsError.domain) code=\(nsError.code)")
            print("🌐 [\(requestId)] Description: \(error.localizedDescription)")
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut {
                print("🌐 [\(requestId)] ⏰ 请求超时（timeout=\(request.timeout)s）")
                throw NetworkError.timeout
            }
            if nsError.domain == NSURLErrorDomain {
                print("🌐 [\(requestId)] 🔌 连接失败 code=\(nsError.code)")
                throw NetworkError.connectionFailed(error)
            }
            throw NetworkError.classify(error, url: request.url)
        }

        let elapsed = Date().timeIntervalSince(startTime)
        guard let http = response as? HTTPURLResponse else {
            print("🌐 [\(requestId)] <<< NOT HTTP \(String(format: "%.1f", elapsed))s")
            throw NetworkError.unknown(URLError(.badServerResponse))
        }

        let statusCode = http.statusCode
        let contentType = http.allHeaderFields["Content-Type"] as? String
            ?? http.allHeaderFields["content-type"] as? String
            ?? ""
        let headers = http.allHeaderFields.reduce(into: [String: String]()) { dict, pair in
            dict["\(pair.key)"] = "\(pair.value)"
        }

        print("""
        🌐 [\(requestId)] <<< HTTP \(statusCode) \(String(format: "%.1f", elapsed))s
        🌐 [\(requestId)]    Content-Type: \(contentType)
        🌐 [\(requestId)]    Body 长度: \(data.count) bytes
        """)

        // 打印 body 摘要
        if data.count > 0 {
            if let text = String(data: data, encoding: .utf8) {
                print("🌐 [\(requestId)]    UTF-8 可解码, 前 2000 字:")
                print(text.prefix(2000))
            } else {
                print("🌐 [\(requestId)]    ⚠️ 非 UTF-8 编码（可能是二进制图片）")
                print("🌐 [\(requestId)]    前 64 字节 hex: \(data.prefix(64).map { String(format: "%02x", $0) }.joined())")
                // 检查是否为常见图片格式
                if data.count >= 4 {
                    let magic = data.prefix(4).map { $0 }
                    let magicStr = magic.map { String(format: "%02x", $0) }.joined()
                    if magicStr.hasPrefix("ffd8") { print("🌐 [\(requestId)]    ⚠️ 检测到 JPEG 文件头") }
                    else if magicStr.hasPrefix("89504e47") { print("🌐 [\(requestId)]    ⚠️ 检测到 PNG 文件头") }
                    else if magicStr.hasPrefix("52494646") { print("🌐 [\(requestId)]    ⚠️ 检测到 WEBP 文件头") }
                    else if magicStr.hasPrefix("474946") { print("🌐 [\(requestId)]    ⚠️ 检测到 GIF 文件头") }
                }
            }
        } else {
            print("🌐 [\(requestId)]    ⚠️ Body 为空")
            // 打印 headers 供参考
            print("🌐 [\(requestId)]    Headers: \(headers)")
        }

        guard (200...299).contains(statusCode) else {
            let msg = String(data: data, encoding: .utf8)
            print("🌐 [\(requestId)] ❌ HTTP \(statusCode)")
            throw NetworkError.httpError(statusCode: statusCode, message: msg, url: request.url)
        }

        return HTTPResponse(data: data, statusCode: statusCode, contentType: contentType, headers: headers)
    }
}
