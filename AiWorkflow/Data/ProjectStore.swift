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
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let items = try JSONDecoder().decode([Project].self, from: data)
            cache = [:]
            for item in items { cache[item.id] = item }
            print("📦 [ProjectStore] load: \(cache.count) projects")
        } catch {
            print("📦 [ProjectStore] load 失败: \(error)")
            // 文件损坏，重置
            cache = [:]
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(Array(cache.values))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("📦 [ProjectStore] save 失败: \(error)")
        }
    }
}
