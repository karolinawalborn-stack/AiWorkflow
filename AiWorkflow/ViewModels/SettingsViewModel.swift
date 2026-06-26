import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    // API 配置
    @Published var apiBaseURL: String
    @Published var apiKey: String
    @Published var textModelID: String
    @Published var imageModelID: String
    @Published var isAPIKeyVisible = false
    @Published var validationResult: String?
    @Published var isValidating = false

    // 三套模板
    @Published var topicTemplate: AITemplate
    @Published var copyTemplate: AITemplate
    @Published var promptTemplate: AITemplate
    @Published var showPreviewFor: String? = nil  // 当前预览哪套模板

    init() {
        let s = UserSettings.load()
        self.apiBaseURL = s.apiBaseURL; self.apiKey = s.apiKey
        self.textModelID = s.textModelID; self.imageModelID = s.imageModelID

        let t = AITemplates.load()
        self.topicTemplate = t.topic
        self.copyTemplate = t.copywriting
        self.promptTemplate = t.imagePrompt
    }

    // MARK: - API 配置

    func save() {
        var s = UserSettings(); s.apiBaseURL = apiBaseURL; s.apiKey = apiKey
        s.textModelID = textModelID; s.imageModelID = imageModelID; s.save()
        saveTemplates()
    }

    func resetAPIToDefaults() {
        apiBaseURL = UserSettings.defaultBaseURL
        apiKey = UserSettings.defaultAPIKey
        textModelID = UserSettings.defaultTextModel
        imageModelID = UserSettings.defaultImageModel
    }

    /// 测试连接：请求 models 列表（轻量检测）
    func validateConnection() async {
        guard !apiBaseURL.isEmpty else { validationResult = "请填写URL"; return }
        guard !apiKey.isEmpty else { validationResult = "请填写Key"; return }
        isValidating = true; validationResult = nil
        let urlStr = "\(apiBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/v1/models"
        guard let url = URL(string: urlStr) else { validationResult = "无效URL"; isValidating = false; return }
        var req = URLRequest(url: url); req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization"); req.timeoutInterval = 15
        let start = Date()
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let elapsed = Date().timeIntervalSince(start)
            if let http = resp as? HTTPURLResponse {
                validationResult = http.statusCode == 200
                    ? "✅ Models 接口 OK (\(String(format: "%.1f", elapsed))s)"
                    : "❌ HTTP \(http.statusCode) (\(String(format: "%.1f", elapsed))s)"
            } else {
                validationResult = "❌ 非 HTTP 响应"
            }
        } catch {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorTimedOut {
                validationResult = "⏰ 超时（15s）"
            } else if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorSecureConnectionFailed {
                validationResult = "🔒 安全连接失败（ATS/证书问题）"
            } else if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorNotConnectedToInternet {
                validationResult = "📡 网络未连接"
            } else {
                validationResult = "❌ \(error.localizedDescription)"
            }
        }
        isValidating = false
    }

    /// 短模板测试：用极短 prompt 验证文本接口是否正常工作
    func shortTest() async {
        guard !apiBaseURL.isEmpty else { validationResult = "请填写URL"; return }
        guard !apiKey.isEmpty else { validationResult = "请填写Key"; return }
        isValidating = true; validationResult = "🔄 发送短文本测试请求..."
        let start = Date()
        print("🧪 [ShortTest] 开始短文本测试")

        // 使用适配器发送一个极简的 chat completion
        let config = AIProviderConfig(baseURL: apiBaseURL, apiKey: apiKey, textModel: textModelID, imageModel: imageModelID, timeout: 30)
        let client = HTTPClient()
        let adapter = InternalToolStationTextAdapter(httpClient: client, config: config)

        do {
            _ = try await adapter.chatCompletion(
                systemPrompt: "你是一个助手。请用一句话回答。",
                userMessage: "你好，请回复：ok",
                temperature: 0.3
            )
            let elapsed = Date().timeIntervalSince(start)
            validationResult = "✅ 短文本测试通过 (\(String(format: "%.1f", elapsed))s)"
            print("✅ [ShortTest] 成功 \(String(format: "%.1f", elapsed))s")
        } catch let ne as NetworkError {
            let elapsed = Date().timeIntervalSince(start)
            validationResult = "❌ [\(ne.category)] \(ne.errorDescription ?? "N/A") (\(String(format: "%.1f", elapsed))s)"
            print("❌ [ShortTest] 失败 \(String(format: "%.1f", elapsed))s: \(ne.category) - \(ne.errorDescription ?? "")")
        } catch {
            let elapsed = Date().timeIntervalSince(start)
            validationResult = "❌ 未知错误 (\(String(format: "%.1f", elapsed))s): \(error.localizedDescription)"
            print("❌ [ShortTest] 未知 \(String(format: "%.1f", elapsed))s: \(error)")
        }
        isValidating = false
    }

    // MARK: - 模板保存

    func saveTemplates() {
        let t = AITemplates(topic: topicTemplate, copywriting: copyTemplate, imagePrompt: promptTemplate)
        t.save()
    }

    /// 获取指定模板的渲染预览
    func preview(for template: AITemplate) -> String {
        template.render()
    }

    /// 恢复全套默认
    func resetAllTemplates() {
        AITemplates.resetToDefaults()
        let t = AITemplates.load()
        topicTemplate = t.topic
        copyTemplate = t.copywriting
        promptTemplate = t.imagePrompt
    }

    /// 恢复单套模板正文
    func resetBody(for id: String) {
        switch id {
        case "topic": topicTemplate = topicTemplate.resetBody()
        case "copywriting": copyTemplate = copyTemplate.resetBody()
        case "imagePrompt": promptTemplate = promptTemplate.resetBody()
        default: break
        }
    }

    /// 恢复单套模板变量
    func resetVariables(for id: String) {
        switch id {
        case "topic": topicTemplate = topicTemplate.resetVariables()
        case "copywriting": copyTemplate = copyTemplate.resetVariables()
        case "imagePrompt": promptTemplate = promptTemplate.resetVariables()
        default: break
        }
    }

    /// 获取模板（按 id）
    func template(for id: String) -> AITemplate? {
        switch id {
        case "topic": return topicTemplate
        case "copywriting": return copyTemplate
        case "imagePrompt": return promptTemplate
        default: return nil
        }
    }

    /// 更新模板
    func updateTemplate(_ t: AITemplate) {
        switch t.id {
        case "topic": topicTemplate = t
        case "copywriting": copyTemplate = t
        case "imagePrompt": promptTemplate = t
        default: break
        }
    }
}
