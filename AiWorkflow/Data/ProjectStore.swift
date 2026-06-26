import Foundation

/// 项目存储（JSON + FileManager）
/// 非 actor，由 @MainActor ViewModel 调用。
final class ProjectStore: @unchecked Sendable {
    private var cache: [UUID: Project] = [:]
    private let fileURL: URL

    var allProjects: [Project] { cache.values.sorted { $0.updatedAt > $1.updatedAt } }

    init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("projects.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    func project(id: UUID) -> Project? { cache[id] }

    func upsert(_ project: Project) {
        var p = project
        p.updatedAt = Date()
        cache[p.id] = p
        save()
    }

    func delete(id: UUID) {
        cache.removeValue(forKey: id)
        save()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let items = try? JSONDecoder().decode([Project].self, from: data)
        else { return }
        cache = [:]
        for item in items { cache[item.id] = item }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(Array(cache.values)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
