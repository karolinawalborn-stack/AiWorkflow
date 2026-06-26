import SwiftUI

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var projects: [Project] = []
    @Published var filterStatus: ProjectStatus?
    @Published var searchText: String = ""
    private var store: ProjectStore?

    func setup(store: ProjectStore) { self.store = store; reload() }

    func reload() {
        guard let s = store else { return }
        var all = s.allProjects
        if let fs = filterStatus { all = all.filter { $0.status == fs } }
        projects = all
    }

    var filteredProjects: [Project] {
        var r = projects
        if !searchText.isEmpty { r = r.filter { $0.name.localizedCaseInsensitiveContains(searchText) } }
        return r
    }

    var groupedByStatus: [(ProjectStatus, [Project])] {
        let g = Dictionary(grouping: filteredProjects) { $0.status }
        return ProjectStatus.allCases.compactMap { s in guard let items = g[s], !items.isEmpty else { return nil }; return (s, items) }
    }

    func deleteById(_ id: UUID) { store?.delete(id: id); reload() }
}
