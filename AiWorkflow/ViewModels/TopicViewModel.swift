import SwiftUI

@MainActor
final class TopicViewModel: ObservableObject {
    @Published var topics: [TopicCandidate] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var positioningInput: String = ""
    @Published var selectedTopicID: UUID?

    var project: Project?
    private var store: ProjectStore?
    private var textService: AITextServiceProtocol?

    static let defaultPositioning = """
    账号定位：抖音爆款双格漫画
    赛道：婚姻情感 / 爱情关系 / 职场压榨 / 亲情委屈 / 人性清醒 / 讨好型人格
    目标受众：20-40 岁，有情感/职场/家庭困扰的年轻人
    视觉风格：深蓝黑压抑情绪漫画，白色圆头小人，上下双格，带字幕框
    文案逻辑：上半格受压/委屈/被消耗 → 下半格清醒/反击/离开/止损
    """

    func setup(store: ProjectStore, textService: AITextServiceProtocol, project: Project) {
        self.store = store; self.textService = textService; self.project = project
        self.topics = project.sortedTopics
        self.selectedTopicID = project.selectedTopicID
        if positioningInput.isEmpty { positioningInput = Self.defaultPositioning }
    }

    func generateTopics() {
        guard !positioningInput.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "请输入定位"; return }
        guard let ts = textService else { return }
        isLoading = true; errorMessage = nil

        Task {
            do {
                let r = try await ts.chatCompletion(systemPrompt: """
                    你是一个抖音双格漫画内容策划。根据账号定位生成6个选题。
                    每个包含 title（15字内吸引人标题）和 description（30字内核心角度）。
                    返回JSON: [{"title":"...","description":"..."}]
                    仅返回JSON。
                    """, userMessage: positioningInput, temperature: 0.8)

                let parsed = try parseJSON(r)
                var p = project!
                p.topicCandidates = parsed.enumerated().map { i, item in
                    TopicCandidate(title: item.title, description: item.desc, sortOrder: i)
                }
                p.status = .topicsReady
                store?.upsert(p); project = p
                topics = p.sortedTopics
                isLoading = false
            } catch {
                errorMessage = "生成失败：\(error.localizedDescription)"; isLoading = false
            }
        }
    }

    func toggleFavorite(_ topic: TopicCandidate) {
        guard let idx = topics.firstIndex(where: { $0.id == topic.id }) else { return }
        topics[idx].isFavorited.toggle()
        var p = project!; p.topicCandidates = topics; store?.upsert(p); project = p
    }

    func selectTopic(_ topic: TopicCandidate) {
        selectedTopicID = topic.id
        var p = project!; p.selectedTopicID = topic.id
        if p.status == .draft || p.status == .topicsReady { p.status = .topicSelected }
        store?.upsert(p); project = p
    }

    private func parseJSON(_ text: String) throws -> [(title: String, desc: String)] {
        let d: Data
        if let data = text.data(using: .utf8) { d = data }
        else if let ex = extractJSON(text) { d = ex }
        else { throw NSError(domain: "Parse", code: -1) }
        guard let j = try JSONSerialization.jsonObject(with: d) as? [[String: String]] else { throw NSError(domain: "Parse", code: -1) }
        return j.compactMap { guard let t = $0["title"] else { return nil }; return (t, $0["description"] ?? "") }
    }

    private func extractJSON(_ text: String) -> Data? {
        guard let r = text.range(of: "```json"), let e = text[r.upperBound...].range(of: "```") else { return nil }
        return String(text[r.upperBound..<e.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8)
    }
}
