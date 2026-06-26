import Foundation

/// 用户设置（UserDefaults 持久化）
struct UserSettings: Codable, Sendable {
    var apiBaseURL: String
    var apiKey: String
    var textModelID: String
    var imageModelID: String
    var defaultTemplateContent: String

    static let defaultBaseURL = "https://api.lk888.ai/api"
    static let defaultTextModel = "gpt-5.4"
    static let defaultImageModel = "gpt-image-2"
    static let defaultAPIKey = "sk-1c22e331ff128e7f4d62eff86a5e2caccdbb67e07db70011"

    init(
        baseURL: String = Self.defaultBaseURL,
        apiKey: String = Self.defaultAPIKey,
        textModel: String = Self.defaultTextModel,
        imageModel: String = Self.defaultImageModel,
        defaultTemplateContent: String = ""
    ) {
        self.apiBaseURL = baseURL
        self.apiKey = apiKey
        self.textModelID = textModel
        self.imageModelID = imageModel
        self.defaultTemplateContent = defaultTemplateContent
    }

    static func load() -> UserSettings {
        let d = UserDefaults.standard
        return UserSettings(
            baseURL: d.string(forKey: "api_base_url") ?? defaultBaseURL,
            apiKey: d.string(forKey: "api_key") ?? "",
            textModel: d.string(forKey: "text_model") ?? defaultTextModel,
            imageModel: d.string(forKey: "image_model") ?? defaultImageModel,
            defaultTemplateContent: d.string(forKey: "default_prompt_template") ?? ""
        )
    }

    func save() {
        let d = UserDefaults.standard
        d.set(apiBaseURL, forKey: "api_base_url")
        d.set(apiKey, forKey: "api_key")
        d.set(textModelID, forKey: "text_model")
        d.set(imageModelID, forKey: "image_model")
        d.set(defaultTemplateContent, forKey: "default_prompt_template")
    }
}
