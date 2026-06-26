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

    func validateConnection() async {
        guard !apiBaseURL.isEmpty else { validationResult = "请填写URL"; return }
        guard !apiKey.isEmpty else { validationResult = "请填写Key"; return }
        isValidating = true; validationResult = nil
        guard let url = URL(string: "\(apiBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/v1/models") else {
            validationResult = "无效URL"; isValidating = false; return
        }
        var req = URLRequest(url: url); req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization"); req.timeoutInterval = 15
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            validationResult = (resp as? HTTPURLResponse)?.statusCode == 200 ? "连接成功" : "连接失败"
        } catch { validationResult = "连接失败：\(error.localizedDescription)" }
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
