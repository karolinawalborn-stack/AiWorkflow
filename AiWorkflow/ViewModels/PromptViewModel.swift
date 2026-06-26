import SwiftUI

@MainActor
final class PromptViewModel: ObservableObject {
    @Published var prompts: [PromptCard] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastCopied: String?
    @Published var rawResponse: String = ""

    var project: Project?
    private var store: ProjectStore?
    private var textService: AITextServiceProtocol?

    func setup(store: ProjectStore, textService: AITextServiceProtocol, project: Project) {
        self.store = store; self.textService = textService; self.project = project
        self.prompts = project.sortedPrompts
        print("📝 [PromptVM] setup: prompts=\(prompts.count), 非空=\(prompts.filter { !$0.prompt.isEmpty }.count)")
    }

    func generatePrompts() {
        print("🔵 [PromptVM] ===== 生成提示词 =====")
        guard let ts = textService else { errorMessage = "AI 服务未初始化"; return }
        guard let p = project else { errorMessage = "项目未加载"; return }
        guard !p.copywritingCards.isEmpty else { errorMessage = "请先生成文案"; return }

        isLoading = true; errorMessage = nil; rawResponse = ""

        let cardsText = p.sortedCopyCards.map {
            "图\($0.cardIndex + 1)上:\($0.topText) | 下:\($0.bottomText)"
        }.joined(separator: "\n")

        var imgTemplate = AITemplates.load().imagePrompt
        if let idx = imgTemplate.variables.firstIndex(where: { $0.key == "top_caption" }) {
            imgTemplate.variables[idx].value = p.sortedCopyCards.map { $0.topText }.joined(separator: " | ")
        }
        if let idx = imgTemplate.variables.firstIndex(where: { $0.key == "bottom_caption" }) {
            imgTemplate.variables[idx].value = p.sortedCopyCards.map { $0.bottomText }.joined(separator: " | ")
        }
        let systemPrompt = imgTemplate.render()
        print("📝 [PromptVM] prompt长度=\(systemPrompt.count)")

        Task {
            do {
                let r = try await ts.chatCompletion(systemPrompt: systemPrompt, userMessage: "IP:\(p.ipStyle)\n比例:\(p.ratio)\n文案:\n\(cardsText)", temperature: 0.7)
                rawResponse = r
                print("📥 [PromptVM] 返回长度=\(r.count), 前200: \(r.prefix(200))")

                // 先试 JSON
                if let parsed = try? parsePromptJSON(r) {
                    var np = p; var npr = np.promptCards
                    var filled = 0
                    for item in parsed where item.index < npr.count {
                        npr[item.index].prompt = item.prompt
                        npr[item.index].imageDescription = item.desc
                        if !item.prompt.isEmpty { filled += 1 }
                    }
                    np.promptCards = npr
                    if np.status == .copyReady || np.status == .topicSelected { np.status = .promptsReady }
                    store?.upsert(np); project = np
                    prompts = npr.sorted { $0.cardIndex < $1.cardIndex }
                    isLoading = false
                    print("✅ [PromptVM] JSON 解析: \(parsed.count) 条, 非空=\(filled)")
                    return
                }

                // JSON 失败，尝试文本解析
                if let textParsed = parsePromptText(r) {
                    var np = p; var npr = np.promptCards
                    var filled = 0
                    for item in textParsed where item.index < npr.count {
                        npr[item.index].prompt = item.prompt
                        npr[item.index].imageDescription = item.desc
                        if !item.prompt.isEmpty { filled += 1 }
                    }
                    np.promptCards = npr
                    if np.status == .copyReady || np.status == .topicSelected { np.status = .promptsReady }
                    store?.upsert(np); project = np
                    prompts = npr.sorted { $0.cardIndex < $1.cardIndex }
                    isLoading = false
                    print("✅ [PromptVM] 文本解析: \(textParsed.count) 条, 非空=\(filled)")
                    return
                }

                print("❌ [PromptVM] 解析失败，原始响应: \(r.prefix(300))")
                errorMessage = "收到响应但未能提取提示词，请查看原始响应"
                isLoading = false

            } catch let ne as NetworkError {
                errorMessage = "生成失败：[\(ne.category)]"
                isLoading = false; print("❌ [PromptVM] \(ne.category)")
            } catch {
                let ns = error as NSError
                if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled {
                    errorMessage = "请求被中断（后台），请重新生成"
                } else { errorMessage = "生成失败：\(error.localizedDescription)" }
                isLoading = false; print("❌ [PromptVM] \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 文本格式提示词解析

    private func parsePromptText(_ text: String) -> [(index: Int, desc: String, prompt: String)]? {
        var results: [(index: Int, desc: String, prompt: String)] = []
        let lines = text.components(separatedBy: .newlines)

        var ci = -1, desc = "", prompt = ""
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("第") && line.contains("张") {
                if ci >= 0 { results.append((ci, desc, prompt)) }
                ci = extractNumber(line) ?? (ci + 1); desc = ""; prompt = ""
                continue
            }

            if line.contains("画面描述") || line.contains("description") || line.contains("Description") {
                let val = extractPromptValue(line)
                if !val.isEmpty { desc = val }
                continue
            }
            if line.contains("prompt") || line.contains("Prompt") || line.contains("提示词") {
                let val = extractPromptValue(line)
                if !val.isEmpty { prompt = val }
                continue
            }
            // 长行可能是提示词本身
            if line.count > 50 && prompt.isEmpty {
                prompt = line
            }
        }
        if ci >= 0 { results.append((ci, desc, prompt)) }

        return results.isEmpty ? nil : results
    }

    private func extractPromptValue(_ line: String) -> String {
        for c in ["：", ":"] {
            if let idx = line.firstIndex(of: c) {
                let val = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
                if !val.isEmpty { return val }
            }
        }
        return ""
    }

    private func extractNumber(_ s: String) -> Int? {
        let digits = s.compactMap { $0.isNumber ? String($0) : nil }.joined()
        return Int(digits)
    }

    // MARK: - JSON 解析

    private func parsePromptJSON(_ text: String) throws -> [(index: Int, desc: String, prompt: String)] {
        let d: Data
        if let data = text.data(using: .utf8) { d = data }
        else if let ex = extractJSON(text) { d = ex }
        else { throw NSError(domain: "Parse", code: -1) }
        guard let j = try JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { throw NSError(domain: "Parse", code: -1) }
        return j.compactMap {
            guard let idx = $0["cardIndex"] as? Int else { return nil }
            let d = ($0["description"] as? String) ?? ($0["desc"] as? String) ?? ""
            let p = ($0["prompt"] as? String) ?? ($0["promptText"] as? String) ?? ""
            return (idx, d, p)
        }
    }

    private func extractJSON(_ text: String) -> Data? {
        guard let r = text.range(of: "```json"), let e = text[r.upperBound...].range(of: "```") else { return nil }
        return String(text[r.upperBound..<e.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8)
    }

    // MARK: - 其他

    func updatePrompt(at index: Int, prompt: String, description: String) {
        guard index < prompts.count else { return }
        prompts[index].prompt = prompt; prompts[index].imageDescription = description
    }

    func copyPrompt(at index: Int) {
        guard index < prompts.count else { return }
        #if os(iOS)
        UIPasteboard.general.string = prompts[index].prompt
        #endif
        lastCopied = prompts[index].prompt
    }

    func copyAllPrompts() {
        let all = prompts.sorted { $0.cardIndex < $1.cardIndex }.map { "【图\($0.cardIndex+1)】\n\($0.prompt)" }.joined(separator: "\n\n---\n\n")
        #if os(iOS)
        UIPasteboard.general.string = all
        #endif
        lastCopied = all
    }

    func saveAsTemplate() {
        let all = prompts.sorted { $0.cardIndex < $1.cardIndex }.map { $0.prompt }.joined(separator: "\n---\n")
        UserDefaults.standard.set(all, forKey: "default_prompt_template")
    }
}
