import SwiftUI

@MainActor
final class PromptViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastCopied: String?
    @Published var rawResponse: String = ""
    @Published var currentGeneratingIndex: Int? = nil

    @Published var project: Project?
    private var store: ProjectStore?
    private var textService: AITextServiceProtocol?
    private var currentTask: Task<Void, Never>?

    // MARK: - 单一数据源：直接从 project 读取

    var prompts: [PromptCard] {
        project?.sortedPrompts ?? []
    }

    /// 实际有内容的卡片数
    var nonEmptyPromptCount: Int {
        prompts.filter { $0.status == .success && !$0.promptText.isEmpty }.count
    }

    // MARK: - 设置

    func setup(store: ProjectStore, textService: AITextServiceProtocol, project: Project) {
        self.store = store
        self.textService = textService
        self.project = project

        let success = project.sortedPrompts.filter { $0.status == .success && !$0.promptText.isEmpty }.count
        let pending = project.sortedPrompts.filter { $0.status == .pending }.count
        let failed = project.sortedPrompts.filter { $0.status == .failed }.count
        print("""
        📝 [PromptVM] setup:
           promptCards=\(project.promptCards.count) 张
           成功=\(success) | 待生成=\(pending) | 失败=\(failed)
           copywritingCards 非空=\(project.copywritingCards.filter { !$0.topText.isEmpty }.count) 张
        """)
        for c in project.sortedCopyCards {
            print("   copy[\(c.cardIndex)] top=「\(c.topText.prefix(30))」 bottom=「\(c.bottomText.prefix(30))」")
        }
        for p in project.sortedPrompts {
            print("   prompt[\(p.cardIndex)] status=\(p.status.rawValue) text=「\(p.promptText.prefix(30))」")
        }
    }

    deinit {
        currentTask?.cancel()
    }

    // MARK: - 逐张生成提示词

    /// 生成所有 6 张的提示词（逐张调用 API）
    func generatePrompts() {
        print("🔵 [PromptVM] ===== 开始逐张生成提示词 =====")
        guard let p = project else { errorMessage = "项目未加载"; return }

        // 先重载项目，获取最新文案
        let freshProject: Project
        if let s = store, let reloaded = s.project(id: p.id) {
            freshProject = reloaded
            project = reloaded
            print("📦 [PromptVM] 从 store 重载项目")
        } else {
            freshProject = p
        }

        let copyCards = freshProject.sortedCopyCards
        guard !copyCards.isEmpty else { errorMessage = "文案为空，请先生成文案"; return }
        guard copyCards.contains(where: { !$0.topText.isEmpty || !$0.bottomText.isEmpty }) else {
            errorMessage = "文案内容为空"; return
        }

        // 检查不需要生成的卡片
        let toGenerate = copyCards.indices.filter { idx in
            freshProject.promptCards.indices.contains(idx) &&
            (freshProject.promptCards[idx].status != .success || freshProject.promptCards[idx].promptText.isEmpty)
        }

        if toGenerate.isEmpty {
            print("✅ [PromptVM] 所有提示词已生成，无需重复生成")
            return
        }

        currentTask?.cancel()
        isLoading = true
        errorMessage = nil
        rawResponse = ""
        currentGeneratingIndex = nil

        // 重置待生成卡片状态
        var np = freshProject
        for idx in toGenerate where idx < np.promptCards.count {
            np.promptCards[idx].status = .pending
            np.promptCards[idx].promptText = ""
            np.promptCards[idx].rawResponse = ""
            np.promptCards[idx].errorMessage = nil
        }
        project = np

        currentTask = Task {
            for (loopIdx, idx) in toGenerate.enumerated() {
                if Task.isCancelled { break }

                print("\n========== [PromptVM] 第\(loopIdx+1)/\(toGenerate.count) 张 (卡片\(idx+1)) ==========")
                await generateSinglePrompt(at: idx)

                // 每张生成后存盘
                if let np2 = project {
                    store?.upsert(np2)
                }
            }

            isLoading = false
            currentGeneratingIndex = nil
            let total = prompts.count
            let done = nonEmptyPromptCount
            print("✅ [PromptVM] 逐张生成完成: \(done)/\(total) 张有内容")
        }
    }

    /// 为单张卡片生成提示词
    private func generateSinglePrompt(at index: Int) async {
        guard let ts = textService else {
            setCardFailed(index, error: "AI 服务未初始化")
            return
        }
        guard var np = project, index < np.copywritingCards.count, index < np.promptCards.count else {
            setCardFailed(index, error: "索引越界")
            return
        }

        let copyCard = np.copywritingCards[index]
        let topText = copyCard.topText
        let bottomText = copyCard.bottomText

        print("📤 [PromptVM] 第\(index+1)张:")
        print("   上半格: 「\(topText)」")
        print("   下半格: 「\(bottomText)」")

        // 如果文案为空，标记 pending 并跳过
        if topText.trimmingCharacters(in: .whitespaces).isEmpty && bottomText.trimmingCharacters(in: .whitespaces).isEmpty {
            print("⚠️ [PromptVM] 第\(index+1)张文案为空，跳过")
            np.promptCards[index].status = .pending
            project = np
            return
        }

        // 标记生成中
        currentGeneratingIndex = index
        np.promptCards[index].status = .generating
        project = np

        // 构建单卡 prompt
        var imgTemplate = AITemplates.load().imagePrompt
        if let vi = imgTemplate.variables.firstIndex(where: { $0.key == "top_caption" }) {
            imgTemplate.variables[vi].value = topText
        }
        if let vi = imgTemplate.variables.firstIndex(where: { $0.key == "bottom_caption" }) {
            imgTemplate.variables[vi].value = bottomText
        }
        let systemPrompt = imgTemplate.render()
        print("📝 [PromptVM] 模板渲染长度=\(systemPrompt.count)")

        let userMessage = "【上半格】文案：\(topText)\n【下半格】文案：\(bottomText)"

        do {
            let r = try await ts.chatCompletion(systemPrompt: systemPrompt, userMessage: userMessage, temperature: 0.7)
            try Task.checkCancellation()

            print("📥 [PromptVM] 第\(index+1)张 API 返回, 长度=\(r.count)")
            print("📥 前200字: \(r.prefix(200))")

            // 直接写入 promptText（不经过 JSON 解析）
            guard var np2 = project, index < np2.promptCards.count else { return }
            np2.promptCards[index].promptText = r
            np2.promptCards[index].rawResponse = r
            np2.promptCards[index].status = .success
            np2.promptCards[index].errorMessage = nil
            np2.updatedAt = Date()
            project = np2

            print("✅ [PromptVM] 第\(index+1)张写入成功! promptText前200字=「\(r.prefix(200))」")
            print("   写入后 promptCards[\(index)]: status=\(np2.promptCards[index].status.rawValue), promptText.isEmpty=\(np2.promptCards[index].promptText.isEmpty)")

        } catch is CancellationError {
            print("⏹ [PromptVM] 第\(index+1)张被取消")
            setCardFailed(index, error: "请求被取消")
        } catch {
            print("❌ [PromptVM] 第\(index+1)张失败: \(error.localizedDescription)")
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled {
                setCardFailed(index, error: "请求被中断（后台）")
            } else {
                setCardFailed(index, error: error.localizedDescription)
            }
        }

        currentGeneratingIndex = nil
    }

    private func setCardFailed(_ index: Int, error: String) {
        guard var np = project, index < np.promptCards.count else { return }
        np.promptCards[index].status = .failed
        np.promptCards[index].errorMessage = error
        np.updatedAt = Date()
        project = np
    }

    /// 重新生成单张
    func regenerateSingle(at index: Int) {
        guard project != nil, index < (project?.promptCards.count ?? 0) else { return }
        print("🔵 [PromptVM] ===== 重新生成第\(index+1)张 =====")

        // 重置这张卡
        var np = project!
        np.promptCards[index].status = .pending
        np.promptCards[index].promptText = ""
        np.promptCards[index].rawResponse = ""
        np.promptCards[index].errorMessage = nil
        project = np

        // 开始逐张生成（只跑这一张）
        currentTask?.cancel()
        isLoading = true
        errorMessage = nil
        currentGeneratingIndex = nil

        currentTask = Task {
            await generateSinglePrompt(at: index)
            if let np2 = project {
                store?.upsert(np2)
            }
            isLoading = false
            currentGeneratingIndex = nil
            print("✅ [PromptVM] 第\(index+1)张重新生成完成")
        }
    }

    // MARK: - 复制

    // MARK: - 批量导入

    /// 批量导入提示词，按分隔符拆分为最多6条
    /// 批量导入提示词，按分隔符拆分为最多6条
    func batchImportPrompts(_ rawText: String) {
        guard var p = project else { return }
        var parts: [String] = []
        // 按"第N条"格式拆分
        let lines = rawText.components(separatedBy: .newlines)
        var current: [String] = []
        for line in lines {
            if line.hasPrefix("第") && line.contains("条") {
                if !current.isEmpty { parts.append(current.joined(separator: "\n").trimmingCharacters(in: .whitespaces)) }
                current = [line]
            } else { current.append(line) }
        }
        if !current.isEmpty { parts.append(current.joined(separator: "\n").trimmingCharacters(in: .whitespaces)) }
        if parts.isEmpty {
            // 空行或---分隔
            let sep = rawText.contains("---") ? "---" : "___"
            if rawText.contains(sep) {
                parts = rawText.components(separatedBy: sep).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            } else {
                parts = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            }
        }
        var np = p
        for i in 0..<min(parts.count, np.promptCards.count) {
            np.promptCards[i].promptText = parts[i].trimmingCharacters(in: .whitespaces)
            np.promptCards[i].status = .success
        }
        np.updatedAt = Date()
        store?.upsert(np)
        project = np
        print("📝 [PromptVM] 批量导入: \(parts.count) 条")
    }

    func copyPrompt(at index: Int) {
        guard index < prompts.count else { return }
        #if os(iOS)
        UIPasteboard.general.string = prompts[index].promptText
        #endif
        lastCopied = prompts[index].promptText
    }

    func copyAllPrompts() {
        let all = prompts.filter { $0.status == .success && !$0.promptText.isEmpty }
            .sorted { $0.cardIndex < $1.cardIndex }
            .map { "【图\($0.cardIndex+1)】\n\($0.promptText)" }
            .joined(separator: "\n\n---\n\n")
        #if os(iOS)
        UIPasteboard.general.string = all
        #endif
        lastCopied = all
    }

    func saveAsTemplate() {
        let all = prompts.filter { $0.status == .success }
            .sorted { $0.cardIndex < $1.cardIndex }
            .map { $0.promptText }
            .joined(separator: "\n---\n")
        UserDefaults.standard.set(all, forKey: "default_prompt_template")
    }
}
