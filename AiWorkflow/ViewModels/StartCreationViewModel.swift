import SwiftUI

/// 开始创作页 ViewModel——用户输入选题后自动创建 Project
@MainActor
final class StartCreationViewModel: ObservableObject {
    @Published var topicInput: String = ""
    @Published var extraRequirements: String = ""
    @Published var isLoading = false

    var isValid: Bool {
        !topicInput.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 创建 Project 并返回 projectID
    func createProject(store: ProjectStore) -> UUID? {
        guard isValid else { return nil }

        let topic = topicInput.trimmingCharacters(in: .whitespaces)
        var p = Project(name: topic)
        p = p
        store.upsert(p)
        print("✅ [StartCreation] 创建项目「\(p.name)」id=\(p.id)")
        return p.id
    }
}
