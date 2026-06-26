import Foundation

/// AI领航局-内部工具站 文本生成适配器（带全链路日志）
final class InternalToolStationTextAdapter: AITextServiceProtocol {
    private let httpClient: HTTPClient
    private let config: AIProviderConfig

    init(httpClient: HTTPClient, config: AIProviderConfig) {
        self.httpClient = httpClient
        self.config = config
    }

    func chatCompletion(systemPrompt: String, userMessage: String, temperature: Double) async throws -> String {
        let startTime = Date()
        let callId = UUID().uuidString.prefix(6)
        print("📤 [\(callId)] InternalToolStationTextAdapter.chatCompletion START")
        print("📤 [\(callId)] model=\(config.textModelName)")
        print("📤 [\(callId)] timeout=\(config.timeout)s")
        print("📤 [\(callId)] baseURL=\(config.baseURL)")
        print("📤 [\(callId)] systemPrompt.length=\(systemPrompt.count)")
        print("📤 [\(callId)] userMessage.length=\(userMessage.count)")

        // 构造请求
        let body = InternalToolStationTextRequest(
            model: config.textModelName,
            messages: [
                InternalTextMessage(role: "system", content: systemPrompt),
                InternalTextMessage(role: "user", content: userMessage),
            ],
            temperature: temperature
        )

        let bodyData: Data
        do {
            bodyData = try JSONEncoder().encode(body)
        } catch {
            print("❌ [\(callId)] 请求编码失败: \(error)")
            throw NetworkError.unknown(error)
        }

        let url = config.textURL(for: "/v1/chat/completions")
        let request = APIRequest(
            method: .post,
            url: url,
            headers: config.authHeaders,
            body: bodyData,
            timeout: config.timeout
        )

        // 发送
        print("📤 [\(callId)] -> POST \(url)")
        print("📤 [\(callId)] -> headers: \(config.authHeaders.keys)")

        let response: InternalToolStationTextResponse
        do {
            response = try await httpClient.send(request)
        } catch let error as NetworkError {
            let elapsed = Date().timeIntervalSince(startTime)
            print("❌ [\(callId)] FAIL after \(String(format: "%.1f", elapsed))s")
            print("❌ [\(callId)] category=\(error.category)")
            print("❌ [\(callId)] detail=\(error.errorDescription ?? "N/A")")
            throw error
        } catch {
            let elapsed = Date().timeIntervalSince(startTime)
            print("❌ [\(callId)] UNEXPECTED after \(String(format: "%.1f", elapsed))s: \(error)")
            throw NetworkError.classify(error, url: url)
        }

        guard let content = response.choices.first?.message.content else {
            print("❌ [\(callId)] 返回 choices 为空或无 content")
            throw NetworkError.noData
        }

        let elapsed = Date().timeIntervalSince(startTime)
        print("✅ [\(callId)] SUCCESS in \(String(format: "%.1f", elapsed))s")
        print("✅ [\(callId)] response.length=\(content.count)")
        print("✅ [\(callId)] response.preview=\(content.prefix(200))")
        return content
    }
}
