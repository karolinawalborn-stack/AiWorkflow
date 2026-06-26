import SwiftUI

@main
struct AiWorkflowApp: App {
    let store: ProjectStore
    let textService: AITextServiceProtocol
    let imageService: AIImageServiceProtocol

    init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AiWorkflowData", isDirectory: true)
        self.store = ProjectStore(directory: dir)

        // 真实 API 模式（AI领航局-内部工具站）
        let settings = UserSettings.load()
        let config = AIProviderConfig(
            baseURL: settings.apiBaseURL,
            apiKey: settings.apiKey,
            textModel: settings.textModelID,
            imageModel: settings.imageModelID
        )
        let client = HTTPClient()
        self.textService = AITextService(httpClient: client, config: config)
        self.imageService = AIImageService(httpClient: client, config: config)

        // 如需 Mock：注释上面6行，取消注释下面2行
        // self.textService = MockTextService()
        // self.imageService = MockImageService()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(\.projectStore, store)
                .environment(\.textService, textService)
                .environment(\.imageService, imageService)
        }
    }
}

// MARK: - Environment Keys

private struct StoreKey: EnvironmentKey {
    static let defaultValue: ProjectStore = ProjectStore(directory: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("AiWorkflowData"))
}

private struct TextKey: EnvironmentKey { static let defaultValue: AITextServiceProtocol = MockTextService() }
private struct ImageKey: EnvironmentKey { static let defaultValue: AIImageServiceProtocol = MockImageService() }

extension EnvironmentValues {
    var projectStore: ProjectStore { get { self[StoreKey.self] } set { self[StoreKey.self] = newValue } }
    var textService: AITextServiceProtocol { get { self[TextKey.self] } set { self[TextKey.self] = newValue } }
    var imageService: AIImageServiceProtocol { get { self[ImageKey.self] } set { self[ImageKey.self] = newValue } }
}
