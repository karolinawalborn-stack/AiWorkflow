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

        // ── 真实 API 模式：AI领航局-内部工具站适配器 ──
        // 如需 Mock，注释下方 5 行，取消注释最后 2 行
        let config = AIProviderConfig.loadFromDefaults()
        let client = HTTPClient()
        self.textService = InternalToolStationTextAdapter(httpClient: client, config: config)
        self.imageService = InternalToolStationImageAdapter(httpClient: client, config: config)
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
