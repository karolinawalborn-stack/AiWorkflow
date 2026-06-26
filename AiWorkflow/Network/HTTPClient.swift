import Foundation

enum HTTPMethod: String, Sendable { case get = "GET", post = "POST" }

struct APIRequest: Sendable {
    let method: HTTPMethod
    let url: String
    let headers: [String: String]
    let body: Data?
    let timeout: TimeInterval
}

/// HTTP 客户端（带详细日志和错误分类）
final class HTTPClient: @unchecked Sendable {
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) { self.session = session }

    func send<T: Decodable>(_ request: APIRequest) async throws -> T {
        let data = try await sendRaw(request)
        do { return try decoder.decode(T.self, from: data) }
        catch {
            throw NetworkError.decodingFailed(error, rawData: data)
        }
    }

    func sendRaw(_ request: APIRequest) async throws -> Data {
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

            // 超时特别标记
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut {
                print("🌐 [\(requestId)] ⏰ 请求超时（timeout=\(request.timeout)s）")
                throw NetworkError.timeout
            }

            // 连接失败（含 ATS/证书问题）
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

        print("🌐 [\(requestId)] <<< HTTP \(http.statusCode) \(String(format: "%.1f", elapsed))s")
        let dataStr = String(data: data, encoding: .utf8) ?? "\(data.count) bytes binary"
        print("🌐 [\(requestId)] Response preview: \(dataStr.prefix(300))")

        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8)
            throw NetworkError.httpError(statusCode: http.statusCode, message: msg, url: request.url)
        }

        return data
    }
}
