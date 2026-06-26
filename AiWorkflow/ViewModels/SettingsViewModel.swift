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
    @Published var topicTemplate: String
    @Published var copyTemplate: String
    @Published var promptTemplate: String

    init() {
        let s = UserSettings.load()
        self.apiBaseURL = s.apiBaseURL; self.apiKey = s.apiKey
        self.textModelID = s.textModelID; self.imageModelID = s.imageModelID

        let t = PromptTemplates.load()
        self.topicTemplate = t.topic
        self.copyTemplate = t.copywriting
        self.promptTemplate = t.imagePrompt
    }

    // MARK: - API 配置

    func save() {
        var s = UserSettings(); s.apiBaseURL = apiBaseURL; s.apiKey = apiKey
        s.textModelID = textModelID; s.imageModelID = imageModelID
        s.save()
    }

    func resetToDefaults() {
        apiBaseURL = UserSettings.defaultBaseURL; apiKey = ""; textModelID = UserSettings.defaultTextModel
        imageModelID = UserSettings.defaultImageModel; save()
        PromptTemplates.resetToDefaults()
        let t = PromptTemplates.load()
        topicTemplate = t.topic; copyTemplate = t.copywriting; promptTemplate = t.imagePrompt
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
        let t = PromptTemplates(topic: topicTemplate, copywriting: copyTemplate, imagePrompt: promptTemplate)
        t.save()
    }
}
