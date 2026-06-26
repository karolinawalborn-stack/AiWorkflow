import Foundation

/// 用户设置（UserDefaults 持久化）
struct UserSettings: Codable, Sendable {
    var apiBaseURL: String
    var apiKey: String
    var textModelID: String
    var imageBaseURL: String
    var imageEndpointPath: String
    var imageModelID: String
    var imageReferenceMode: String
    var referenceImageFieldName: String
    var imagePromptFieldName: String
    var imageSize: String
    var defaultTemplateContent: String

    static let defaultBaseURL = "https://api.lk888.ai/api"
    static let defaultImageBaseURL = "https://api.lk888.ai"
    static let defaultImageEndpointPath = "/v1/media/generate"
    static let defaultTextModel = "gpt-5.4"
    static let defaultImageModel = "gpt-image-2"
    static let defaultAPIKey = "sk-1c22e331ff128e7f4d62eff86a5e2caccdbb67e07db70011"
    static let defaultImageReferenceMode = "promptOnlyFallback"
    static let defaultReferenceImageFieldName = "image"
    static let defaultImagePromptFieldName = "prompt"
    static let defaultImageSize = "1024x1536"

    init(
        baseURL: String = Self.defaultBaseURL,
        apiKey: String = Self.defaultAPIKey,
        textModel: String = Self.defaultTextModel,
        imageBaseURL: String = Self.defaultImageBaseURL,
        imageEndpointPath: String = Self.defaultImageEndpointPath,
        imageModel: String = Self.defaultImageModel,
        imageReferenceMode: String = Self.defaultImageReferenceMode,
        referenceImageFieldName: String = Self.defaultReferenceImageFieldName,
        imagePromptFieldName: String = Self.defaultImagePromptFieldName,
        imageSize: String = Self.defaultImageSize,
        defaultTemplateContent: String = ""
    ) {
        self.apiBaseURL = baseURL
        self.apiKey = apiKey
        self.textModelID = textModel
        self.imageBaseURL = imageBaseURL
        self.imageEndpointPath = imageEndpointPath
        self.imageModelID = imageModel
        self.imageReferenceMode = imageReferenceMode
        self.referenceImageFieldName = referenceImageFieldName
        self.imagePromptFieldName = imagePromptFieldName
        self.imageSize = imageSize
        self.defaultTemplateContent = defaultTemplateContent
    }

    static func load() -> UserSettings {
        let d = UserDefaults.standard
        return UserSettings(
            baseURL: d.string(forKey: "api_base_url") ?? defaultBaseURL,
            apiKey: d.string(forKey: "api_key") ?? "",
            textModel: d.string(forKey: "text_model") ?? defaultTextModel,
            imageBaseURL: d.string(forKey: "image_base_url") ?? defaultImageBaseURL,
            imageEndpointPath: d.string(forKey: "image_endpoint_path") ?? defaultImageEndpointPath,
            imageModel: d.string(forKey: "image_model") ?? defaultImageModel,
            imageReferenceMode: d.string(forKey: "image_reference_mode") ?? defaultImageReferenceMode,
            referenceImageFieldName: d.string(forKey: "reference_image_field_name") ?? defaultReferenceImageFieldName,
            imagePromptFieldName: d.string(forKey: "image_prompt_field_name") ?? defaultImagePromptFieldName,
            defaultTemplateContent: d.string(forKey: "default_prompt_template") ?? ""
        )
    }

    func save() {
        let d = UserDefaults.standard
        d.set(apiBaseURL, forKey: "api_base_url")
        d.set(apiKey, forKey: "api_key")
        d.set(textModelID, forKey: "text_model")
        d.set(imageBaseURL, forKey: "image_base_url")
        d.set(imageEndpointPath, forKey: "image_endpoint_path")
        d.set(imageModelID, forKey: "image_model")
        d.set(imageReferenceMode, forKey: "image_reference_mode")
        d.set(referenceImageFieldName, forKey: "reference_image_field_name")
        d.set(imagePromptFieldName, forKey: "image_prompt_field_name")
        d.set(imageSize, forKey: "image_size")
        d.set(defaultTemplateContent, forKey: "default_prompt_template")
    }
}
