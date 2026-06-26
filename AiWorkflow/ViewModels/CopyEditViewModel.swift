import SwiftUI

///
/// 文案编辑 ViewModel — 单一数据源设计
///
/// 唯一文案数据源：project.copywritingCards
/// 所有读/写都直接走 project，不再维护局部副本。
///
@MainActor
final class CopyEditViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var progressText: String = ""
    @Published var userTopic: String = ""
    @Published var extraRequirements: String = ""
    @Published var rawResponse: String = ""
    @Published var parseMode: String = ""

    @Published var project: Project?
    private var store: ProjectStore?
    private var textService: AITextServiceProtocol?
    private var currentTask: Task<Void, Never>?

    // MARK: - 单一数据源：直接从 project 读取，无局部副本

    /// 排序后的文案卡片（UI 唯一数据源）
    var cards: [CopywritingCard] {
        project?.sortedCopyCards ?? []
    }

    /// 非空格数（上下两格都有内容才算）
    var nonEmptyCardCount: Int {
        cards.filter { !$0.topText.isEmpty && !$0.bottomText.isEmpty }.count
    }

    /// 文案是否完整生成（6 张且每张都有上下格内容）
    var isCopyReady: Bool {
        cards.count == 6 && cards.allSatisfy { !$0.topText.isEmpty && !$0.bottomText.isEmpty }
    }

    // MARK: - 设置

    func setup(store: ProjectStore, textService: AITextServiceProtocol, project: Project, userTopic: String, extraRequirements: String) {
        self.store = store
        self.textService = textService
        self.project = project
        self.userTopic = userTopic
        self.extraRequirements = extraRequirements

        let filled = project.copywritingCards.filter { !$0.topText.isEmpty }
        print("""
        📝 [CopyEdit] setup:
           topic=\(userTopic.prefix(30))...
           project.cards=\(project.copywritingCards.count) 张
           非空=\(filled.count) 张
        """)
        for c in project.sortedCopyCards {
            print("   card[\(c.cardIndex)] top=「\(c.topText.prefix(30))」 bottom=「\(c.bottomText.prefix(30))」")
        }
    }

    deinit {
        currentTask?.cancel()
    }

    /// 持久化当前 project 到 store
    func saveProject() {
        guard let p = project, let s = store else { return }
        var np = p
        np.updatedAt = Date()
        s.upsert(np)
        project = np
    }

    // MARK: - 生成文案

    func generateCopy() {
        print("🔵 [CopyEdit] ===== 生成文案 =====")

        guard let ts = textService else { errorMessage = "AI 服务未初始化"; return }
        guard let p = project else { errorMessage = "项目未加载"; return }
        let topic = userTopic.trimmingCharacters(in: .whitespaces)
        guard !topic.isEmpty else { errorMessage = "选题为空"; return }

        currentTask?.cancel()
        isLoading = true
        errorMessage = nil
        progressText = "正在生成文案..."
        rawResponse = ""
        parseMode = ""

        var copyTemplate = AITemplates.load().copywriting
        if let idx = copyTemplate.variables.firstIndex(where: { $0.key == "selected_topic" }) {
            copyTemplate.variables[idx].value = topic
        }
        let systemPrompt = copyTemplate.render()
        print("📝 [CopyEdit] prompt 长度=\(systemPrompt.count)")

        let userMessage = "选题：\(topic)\n图数：\(p.imageCount) 张\n比例：\(p.ratio)\n风格：\(p.ipStyle)\(extraRequirements.isEmpty ? "" : "\n补充要求：\(extraRequirements)")"

        currentTask = Task {
            do {
                let start = Date()
                let r = try await ts.chatCompletion(systemPrompt: systemPrompt, userMessage: userMessage, temperature: 0.8)
                try Task.checkCancellation()

                let elapsed = Date().timeIntervalSince(start)
                print("✅ [CopyEdit] API 返回 (\(String(format: "%.1f", elapsed))s)")
                rawResponse = r
                print("📥 [CopyEdit] 前300字: \(r.prefix(300))")

                let result = CopywritingParser.parse(rawText: r, expectedCount: p.imageCount)
                parseMode = result.mode.rawValue

                if let err = result.error {
                    print("❌ [CopyEdit] 解析失败: \(err)")
                    errorMessage = "解析失败：\(err)"
                    isLoading = false; progressText = ""
                    return
                }

                // ── 调试日志：解析结果 ──
                print("📊 [CopyEdit] 解析结果: \(result.cards.count)张")
                for c in result.cards {
                    print("   card[\(c.cardIndex)] top=「\(c.topText.prefix(40))」 bottom=「\(c.bottomText.prefix(40))」 purpose=「\(c.purpose)」")
                }

                let withTop = result.cards.filter { !$0.topText.isEmpty }
                let withBottom = result.cards.filter { !$0.bottomText.isEmpty }
                if withTop.count == 0 && withBottom.count == 0 {
                    print("❌ [CopyEdit] 解析返回0张有效卡片！原始响应前500字: \(r.prefix(500))")
                    errorMessage = "收到响应但未能提取文案内容，请查看原始响应"
                    isLoading = false; progressText = ""
                    return
                }

                // ── 写入 project（唯一数据源） ──
                var np = p
                np.copywritingCards = result.cards
                if np.status == .draft || np.status == .topicsReady || np.status == .topicSelected {
                    np.status = .copyReady
                }
                np.updatedAt = Date()
                store?.upsert(np)
                project = np

                // ── 调试日志：写入后验证 ──
                print("📝 [CopyEdit] 写入后 project.copywritingCards:")
                for c in np.sortedCopyCards {
                    print("   card[\(c.cardIndex)] top=「\(c.topText.prefix(40))」 bottom=「\(c.bottomText.prefix(40))」")
                }

                isLoading = false
                let total = np.copywritingCards.count
                let nonEmpty = np.copywritingCards.filter { !$0.topText.isEmpty && !$0.bottomText.isEmpty }.count
                progressText = "✅ \(nonEmpty)/\(total) 张已生成（\(result.mode.rawValue)）"
                print("✅ [CopyEdit] 完成: \(nonEmpty)/\(total) 张, 模式=\(result.mode.rawValue)")

            } catch is CancellationError {
                print("⏹ [CopyEdit] 请求被取消（可能 App 进入后台）")
                errorMessage = "应用进入后台，当前请求已中断，请重新生成"
                isLoading = false; progressText = ""
            } catch let ne as NetworkError {
                if case .connectionFailed(let e) = ne {
                    let ns = e as NSError
                    if ns.domain == NSURLErrorDomain {
                        switch ns.code {
                        case NSURLErrorCancelled:
                            print("⏹ [CopyEdit] 请求被取消（后台/主动）")
                            errorMessage = "应用进入后台，当前请求已中断，请重新生成"
                        case NSURLErrorNetworkConnectionLost:
                            print("⏹ [CopyEdit] 网络连接断开")
                            errorMessage = "网络连接断开，请检查网络后重试"
                        default:
                            errorMessage = "网络错误：\(ns.localizedDescription)"
                        }
                        isLoading = false; progressText = ""
                        return
                    }
                }
                errorMessage = "生成失败：[\(ne.category)] \(ne.errorDescription ?? "")"
                isLoading = false; progressText = ""
                print("❌ [CopyEdit] [\(ne.category)]")
            } catch {
                let ns = error as NSError
                if ns.domain == NSURLErrorDomain {
                    switch ns.code {
                    case NSURLErrorCancelled:
                        errorMessage = "应用进入后台，当前请求已中断，请重新生成"
                    case NSURLErrorNetworkConnectionLost:
                        errorMessage = "网络连接断开，请检查网络后重试"
                    default:
                        errorMessage = "网络错误：\(ns.localizedDescription)"
                    }
                } else {
                    errorMessage = "生成失败：\(error.localizedDescription)"
                }
                isLoading = false; progressText = ""
                print("❌ [CopyEdit] \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 本地测试

    func loadMockCopy() {
        print("🧪 [CopyEdit] ===== 加载测试文案 =====")
        currentTask?.cancel()
        isLoading = false; errorMessage = nil; rawResponse = ""; parseMode = "local"

        var mock: [CopywritingCard] = []
        let items: [(Int, String, String, String)] = [
            (0, "你又一次把聊天记录翻到最上面", "原来一个人变心前连标点符号都会变", "钩子，制造代入感"),
            (1, "他说只是加班，你信了", "一个装睡的人叫不醒，但你可以选择先醒", "现实场景"),
            (2, "领导拍拍你的肩说能者多劳", "能者多劳的下半句是——多劳者未必多得", "放大委屈"),
            (3, "你妈说：不结婚就是不孝", "孝顺不是活成别人想要的样子", "点破本质"),
            (4, "你帮他找了一万种借口", "你值得被明目张胆的偏爱", "开始清醒"),
            (5, "你说没事，然后一个人把委屈咽了回去", "从今天起先照顾好自己，再对世界温柔", "金句收尾"),
        ]
        for (idx, top, bottom, purpose) in items {
            let card = CopywritingCard(cardIndex: idx, topText: top, bottomText: bottom, purpose: purpose)
            mock.append(card)
            print("   card[\(idx)] top=\(top.prefix(20))... bottom=\(bottom.prefix(20))...")
        }

        // ── 写入 project（唯一数据源） ──
        var np = project ?? Project(name: "测试项目")
        np.copywritingCards = mock
        np.status = .copyReady
        np.updatedAt = Date()
        store?.upsert(np)
        project = np

        progressText = "🧪 测试文案 \(mock.count) 张"
        parseMode = "local"

        print("🔍 [CopyEdit] 写入后 project.copywritingCards 验证:")
        for c in np.sortedCopyCards {
            print("   card[\(c.cardIndex)] topText=「\(c.topText)」 bottomText=「\(c.bottomText)」 purpose=「\(c.purpose)」")
        }
    }

    // MARK: - 编辑（直接写入 project + 持久化）

    func updateCard(index: Int, topText: String, bottomText: String, purpose: String = "") {
        guard var p = project, index < p.copywritingCards.count else {
            print("⚠️ [CopyEdit] updateCard 跳过: index=\(index), cards.count=\(project?.copywritingCards.count ?? -1)")
            return
        }
        p.copywritingCards[index].topText = topText
        p.copywritingCards[index].bottomText = bottomText
        p.copywritingCards[index].purpose = purpose
        p.copywritingCards[index].isEdited = true
        p.updatedAt = Date()
        store?.upsert(p)
        project = p
        #if DEBUG
        print("📝 [CopyEdit] updateCard[\(index)]: top=「\(topText)」 bottom=「\(bottomText)」")
        #endif
    }
}
