import SwiftUI

@MainActor
final class PromptViewModel: ObservableObject {
    @Published var prompts: [PromptCard] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastCopied: String?

    var project: Project?
    private var store: ProjectStore?
    private var textService: AITextServiceProtocol?

    func setup(store: ProjectStore, textService: AITextServiceProtocol, project: Project) {
        self.store = store; self.textService = textService; self.project = project
        self.prompts = project.sortedPrompts
    }

    func generatePrompts() {
        guard let ts = textService, let p = project else { return }
        guard !p.copywritingCards.isEmpty else { errorMessage = "请先生成文案"; return }
        isLoading = true; errorMessage = nil

        let cardsText = p.sortedCopyCards.map {
            "图\($0.cardIndex + 1)上:\($0.topFrame) | 下:\($0.bottomFrame)"
        }.joined(separator: "\n")

        Task {
            do {
                let r = try await ts.chatCompletion(systemPrompt: """
                    你是GPT Image 2生图提示词专家。根据双格漫画文案生成英文提示词。
                    风格：白色圆头小人IP，深蓝黑压抑情绪背景，上下双格布局，带中文字幕框，3:4竖版。
                    每张图包含上下双格，上格显示上半部分场景，下格显示下半部分场景。
                    返回JSON: [{"cardIndex":0,"description":"中文画面描述","prompt":"英文完整提示词"}]
                    仅返回JSON。
                    """, userMessage: "IP:\(p.ipStyle)\n比例:\(p.ratio)\n文案:\n\(cardsText)", temperature: 0.7)

                let parsed = try parsePromptJSON(r)
                var np = p
                var npr = np.promptCards
                for item in parsed where item.index < npr.count {
                    npr[item.index].prompt = item.prompt
                    npr[item.index].imageDescription = item.desc
                }
                np.promptCards = npr
                if np.status == .copyReady || np.status == .topicSelected { np.status = .promptsReady }
                store?.upsert(np); project = np
                prompts = npr.sorted { $0.cardIndex < $1.cardIndex }
                isLoading = false
            } catch {
                errorMessage = "生成失败：\(error.localizedDescription)"; isLoading = false
            }
        }
    }

    func updatePrompt(at index: Int, prompt: String, description: String) {
        guard index < prompts.count else { return }
        prompts[index].prompt = prompt; prompts[index].imageDescription = description
        var p = project!; p.promptCards = prompts; store?.upsert(p); project = p
    }

    func copyPrompt(at index: Int) { guard index < prompts.count else { return }
        #if os(iOS); UIPasteboard.general.string = prompts[index].prompt; #endif; lastCopied = prompts[index].prompt }

    func copyAllPrompts() {
        let all = prompts.sorted { $0.cardIndex < $1.cardIndex }.map { "【图\($0.cardIndex+1)】\n\($0.prompt)" }.joined(separator: "\n\n---\n\n")
        #if os(iOS); UIPasteboard.general.string = all; #endif; lastCopied = all
    }

    func saveAsTemplate() {
        let all = prompts.sorted { $0.cardIndex < $1.cardIndex }.map { $0.prompt }.joined(separator: "\n---\n")
        UserDefaults.standard.set(all, forKey: "default_prompt_template")
    }

    private func parsePromptJSON(_ text: String) throws -> [(index: Int, desc: String, prompt: String)] {
        let d: Data
        if let data = text.data(using: .utf8) { d = data }
        else if let ex = extractJSON(text) { d = ex }
        else { throw NSError(domain: "Parse", code: -1) }
        guard let j = try JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { throw NSError(domain: "Parse", code: -1) }
        return j.compactMap {
            guard let idx = $0["cardIndex"] as? Int, let d = $0["description"] as? String, let p = $0["prompt"] as? String else { return nil }
            return (idx, d, p)
        }
    }

    private func extractJSON(_ text: String) -> Data? {
        guard let r = text.range(of: "```json"), let e = text[r.upperBound...].range(of: "```") else { return nil }
        return String(text[r.upperBound..<e.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8)
    }
}
