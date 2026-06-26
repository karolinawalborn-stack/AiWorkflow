import SwiftUI

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var projects: [Project] = []
    @Published var searchText: String = ""
    private var store: ProjectStore?

    var recentProjects: [Project] { Array(projects.prefix(5)) }
    var filteredProjects: [Project] {
        if searchText.isEmpty { return projects }
        return projects.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    func setup(store: ProjectStore) { self.store = store; reload() }
    func reload() { projects = store?.allProjects ?? [] }

    func createProject(name: String) -> Project {
        let p = Project(name: name)
        store?.upsert(p); reload(); return p
    }

    func deleteProject(_ project: Project) {
        store?.delete(id: project.id); reload()
    }
}
