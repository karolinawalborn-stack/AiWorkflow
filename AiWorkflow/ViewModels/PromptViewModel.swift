import SwiftUI

@MainActor
final class PromptViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastCopied: String?
    @Published var rawResponse: String = ""

    @Published var project: Project?
    private var store: ProjectStore?
    private var textService: AITextServiceProtocol?

    // MARK: - 单一数据源：直接从 project 读取

    /// 排序后的生图提示词（UI 唯一数据源）
    var prompts: [PromptCard] {
        project?.sortedPrompts ?? []
    }

    var nonEmptyPromptCount: Int {
        prompts.filter { !$0.prompt.isEmpty }.count
    }

    // MARK: - 设置

    func setup(store: ProjectStore, textService: AITextServiceProtocol, project: Project) {
        self.store = store
        self.textService = textService
        self.project = project

        let nonEmpty = project.sortedPrompts.filter { !$0.prompt.isEmpty }.count
        print("""
        📝 [PromptVM] setup:
           project 加载完成
           copywritingCards=\(project.copywritingCards.count) 张
           promptCards=\(project.promptCards.count) 张, 非空=\(nonEmpty)
        """)

        // 调试：打印文案数据源
        for c in project.sortedCopyCards {
            print("   copy[\(c.cardIndex)] top=「\(c.topText.prefix(30))」 bottom=「\(c.bottomText.prefix(30))」")
        }
    }

    // MARK: - 持久化

    private func saveProject() {
        guard let p = project, let s = store else { return }
        var np = p
        np.updatedAt = Date()
        s.upsert(np)
        project = np
    }

    // MARK: - 生成提示词

    func generatePrompts() {
        print("🔵 [PromptVM] ===== 生成提示词 =====")
        guard let ts = textService else { errorMessage = "AI 服务未初始化"; return }
        guard let p = project else { errorMessage = "项目未加载"; return }

        // 关键修复：从 store 重新加载项目，获取最新文案
        let freshProject: Project
        if let s = store, let reloaded = s.project(id: p.id) {
            freshProject = reloaded
            project = reloaded
            print("📦 [PromptVM] 从 store 重新加载 project，获取最新文案")
        } else {
            freshProject = p
        }

        guard !freshProject.copywritingCards.isEmpty else {
            errorMessage = "请先生成文案"
            isLoading = false
            return
        }

        // ── 调试日志：从哪份数据读取文案 ──
        print("📊 [PromptVM] 当前文案数据源验证:")
        for c in freshProject.sortedCopyCards {
            let topEmpty = c.topText.isEmpty ? "⚠️空" : "✅"
            let bottomEmpty = c.bottomText.isEmpty ? "⚠️空" : "✅"
            print("   card[\(c.cardIndex)] top=\(topEmpty)「\(c.topText.prefix(30))」 bottom=\(bottomEmpty)「\(c.bottomText.prefix(30))」")
        }

        let hasContent = freshProject.sortedCopyCards.contains { !$0.topText.isEmpty || !$0.bottomText.isEmpty }
        guard hasContent else {
            errorMessage = "文案内容为空，请先生成文案"
            print("❌ [PromptVM] 文案卡片全部为空！")
            return
        }

        isLoading = true; errorMessage = nil; rawResponse = ""

        let cardsText = freshProject.sortedCopyCards.map {
            "图\($0.cardIndex + 1)上:\($0.topText) | 下:\($0.bottomText)"
        }.joined(separator: "\n")

        var imgTemplate = AITemplates.load().imagePrompt
        if let idx = imgTemplate.variables.firstIndex(where: { $0.key == "top_caption" }) {
            imgTemplate.variables[idx].value = freshProject.sortedCopyCards.map { $0.topText }.joined(separator: " | ")
        }
        if let idx = imgTemplate.variables.firstIndex(where: { $0.key == "bottom_caption" }) {
            imgTemplate.variables[idx].value = freshProject.sortedCopyCards.map { $0.bottomText }.joined(separator: " | ")
        }
        let systemPrompt = imgTemplate.render()
        print("📝 [PromptVM] prompt长度=\(systemPrompt.count)")

        Task {
            do {
                let r = try await ts.chatCompletion(systemPrompt: systemPrompt, userMessage: "IP:\(freshProject.ipStyle)\n比例:\(freshProject.ratio)\n文案:\n\(cardsText)", temperature: 0.7)
                rawResponse = r
                print("📥 [PromptVM] 返回长度=\(r.count), 前200: \(r.prefix(200))")

                // 先试 JSON
                if let parsed = try? parsePromptJSON(r) {
                    var np = freshProject
                    let oldCount = np.promptCards.count
                    // 如果 promptCards 数量不对，先重置
                    if np.promptCards.count != np.imageCount {
                        np.promptCards = (0..<np.imageCount).map { PromptCard(cardIndex: $0) }
                        print("📦 [PromptVM] 重置 promptCards: \(oldCount) → \(np.imageCount)")
                    }
                    var filled = 0
                    for item in parsed where item.index < np.promptCards.count {
                        np.promptCards[item.index].prompt = item.prompt
                        np.promptCards[item.index].imageDescription = item.desc
                        if !item.prompt.isEmpty { filled += 1 }
                    }
                    if np.status == .copyReady || np.status == .topicSelected { np.status = .promptsReady }
                    np.updatedAt = Date()
                    store?.upsert(np)
                    project = np

                    isLoading = false
                    print("✅ [PromptVM] JSON 解析: \(parsed.count) 条, 非空=\(filled)")
                    print("📝 [PromptVM] 写入后 promptCards:")
                    for pr in np.sortedPrompts {
                        print("   prompt[\(pr.cardIndex)] text=「\(pr.prompt.prefix(40))」")
                    }
                    return
                }

                // JSON 失败，尝试文本解析
                if let textParsed = parsePromptText(r) {
                    var np = freshProject
                    let oldCount = np.promptCards.count
                    if np.promptCards.count != np.imageCount {
                        np.promptCards = (0..<np.imageCount).map { PromptCard(cardIndex: $0) }
                        print("📦 [PromptVM] 重置 promptCards: \(oldCount) → \(np.imageCount)")
                    }
                    var filled = 0
                    for item in textParsed where item.index < np.promptCards.count {
                        np.promptCards[item.index].prompt = item.prompt
                        np.promptCards[item.index].imageDescription = item.desc
                        if !item.prompt.isEmpty { filled += 1 }
                    }
                    if np.status == .copyReady || np.status == .topicSelected { np.status = .promptsReady }
                    np.updatedAt = Date()
                    store?.upsert(np)
                    project = np

                    isLoading = false
                    print("✅ [PromptVM] 文本解析: \(textParsed.count) 条, 非空=\(filled)")
                    print("📝 [PromptVM] 写入后 promptCards:")
                    for pr in np.sortedPrompts {
                        print("   prompt[\(pr.cardIndex)] text=「\(pr.prompt.prefix(40))」")
                    }
                    return
                }

                print("❌ [PromptVM] 解析失败，原始响应: \(r.prefix(300))")
                errorMessage = "收到响应但未能提取提示词，请查看原始响应"
                isLoading = false

            } catch let ne as NetworkError {
                let ns = ne as NSError
                if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled {
                    errorMessage = "请求被中断（后台），请重新生成"
                } else {
                    errorMessage = "生成失败：[\(ne.category)]"
                }
                isLoading = false
                print("❌ [PromptVM] \(ne.category)")
            } catch {
                let ns = error as NSError
                if ns.domain == NSURLErrorDomain {
                    switch ns.code {
                    case NSURLErrorCancelled:
                        errorMessage = "请求被中断（后台），请重新生成"
                    case NSURLErrorNetworkConnectionLost:
                        errorMessage = "网络连接断开，请检查网络后重试"
                    default:
                        errorMessage = "网络错误：\(ns.localizedDescription)"
                    }
                } else {
                    errorMessage = "生成失败：\(error.localizedDescription)"
                }
                isLoading = false
                print("❌ [PromptVM] \(error.localizedDescription)")
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
            if line.count > 50 && prompt.isEmpty {
                prompt = line
            }
        }
        if ci >= 0 { results.append((ci, desc, prompt)) }

        return results.isEmpty ? nil : results
    }

    private func extractPromptValue(_ line: String) -> String {
        let colonChars: [Character] = ["：", ":"]
        for c in colonChars {
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
        guard var p = project, index < p.promptCards.count else { return }
        p.promptCards[index].prompt = prompt
        p.promptCards[index].imageDescription = description
        p.updatedAt = Date()
        store?.upsert(p)
        project = p
        print("📝 [PromptVM] updatePrompt[\(index)]: prompt=「\(prompt.prefix(30))」")
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
