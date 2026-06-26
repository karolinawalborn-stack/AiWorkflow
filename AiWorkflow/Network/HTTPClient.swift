import Foundation

enum HTTPMethod: String, Sendable { case get = "GET", post = "POST" }

struct APIRequest: Sendable {
    let method: HTTPMethod
    let url: String
    let headers: [String: String]
    let body: Data?
    let timeout: TimeInterval
}

/// 线程安全的 HTTP 客户端
final class HTTPClient: @unchecked Sendable {
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) { self.session = session }

    func send<T: Decodable>(_ request: APIRequest) async throws -> T {
        let data = try await sendRaw(request)
        do { return try decoder.decode(T.self, from: data) }
        catch { throw NetworkError.decodingFailed(error) }
    }

    func sendRaw(_ request: APIRequest) async throws -> Data {
        guard let url = URL(string: request.url) else { throw NetworkError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = request.method.rawValue
        req.allHTTPHeaderFields = request.headers
        req.httpBody = request.body
        req.timeoutInterval = request.timeout

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: req) }
        catch { throw NetworkError.unknown(error) }

        guard let http = response as? HTTPURLResponse else { throw NetworkError.unknown(URLError(.badServerResponse)) }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8)
            throw NetworkError.httpError(statusCode: http.statusCode, message: msg)
        }
        return data
    }
}
