import SwiftUI

@MainActor
final class CopyEditViewModel: ObservableObject {
    @Published var cards: [CopywritingCard] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var progressText: String = ""
    @Published var selectedTopic: TopicCandidate?

    var project: Project?
    private var store: ProjectStore?
    private var textService: AITextServiceProtocol?

    func setup(store: ProjectStore, textService: AITextServiceProtocol, project: Project) {
        self.store = store; self.textService = textService; self.project = project
        self.cards = project.sortedCopyCards
        self.selectedTopic = project.selectedTopic
    }

    func generateCopy() {
        guard let ts = textService, let p = project else { return }
        isLoading = true; errorMessage = nil; progressText = "正在生成文案..."

        let topicTitle = selectedTopic?.title ?? p.name
        var copyTemplate = AITemplates.load().copywriting
        // 注入当前选题到变量
        if let idx = copyTemplate.variables.firstIndex(where: { $0.key == "selected_topic" }) {
            copyTemplate.variables[idx].value = topicTitle
        }
        let systemPrompt = copyTemplate.render()
        let userMessage = "为「\(topicTitle)」生成\(p.imageCount)张图。\n赛道：\(p.category)\n风格：\(p.style)"
        Task {
            do {
                let r = try await ts.chatCompletion(systemPrompt: systemPrompt, userMessage: userMessage, temperature: 0.8)

                let parsed = try parseCopyJSON(r)
                var np = p
                var nc = np.copywritingCards
                for item in parsed where item.index < nc.count {
                    nc[item.index].topFrame = item.top
                    nc[item.index].bottomFrame = item.bottom
                }
                np.copywritingCards = nc
                if np.status == .topicSelected || np.status == .draft || np.status == .topicsReady { np.status = .copyReady }
                store?.upsert(np); project = np
                cards = nc.sorted { $0.cardIndex < $1.cardIndex }
                isLoading = false; progressText = "文案生成完成"
            } catch {
                errorMessage = "生成失败：\(error.localizedDescription)"; isLoading = false; progressText = ""
            }
        }
    }

    func updateCard(index: Int, top: String, bottom: String) {
        guard index < cards.count else { return }
        cards[index].topFrame = top; cards[index].bottomFrame = bottom; cards[index].isEdited = true
        var p = project!; p.copywritingCards = cards; store?.upsert(p); project = p
    }

    private func parseCopyJSON(_ text: String) throws -> [(index: Int, top: String, bottom: String)] {
        let d: Data
        if let data = text.data(using: .utf8) { d = data }
        else if let ex = extractJSON(text) { d = ex }
        else { throw NSError(domain: "Parse", code: -1) }
        guard let j = try JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { throw NSError(domain: "Parse", code: -1) }
        return j.compactMap {
            guard let idx = $0["cardIndex"] as? Int, let t = $0["topFrame"] as? String, let b = $0["bottomFrame"] as? String else { return nil }
            return (idx, t, b)
        }
    }

    private func extractJSON(_ text: String) -> Data? {
        guard let r = text.range(of: "```json"), let e = text[r.upperBound...].range(of: "```") else { return nil }
        return String(text[r.upperBound..<e.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8)
    }
}
