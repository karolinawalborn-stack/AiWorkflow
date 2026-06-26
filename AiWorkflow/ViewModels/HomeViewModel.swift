import SwiftUI

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var projects: [Project] = []
    private var store: ProjectStore?

    var recentProjects: [Project] { Array(projects.prefix(5)) }

    func setup(store: ProjectStore) {
        self.store = store
        reload()
    }

    func reload() {
        projects = store?.allProjects ?? []
    }
}
