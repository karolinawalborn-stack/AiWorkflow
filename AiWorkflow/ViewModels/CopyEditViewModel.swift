import SwiftUI

@MainActor
final class CopyEditViewModel: ObservableObject {
    // UI 状态
    @Published var cards: [CopywritingCard] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var progressText: String = ""
    @Published var userTopic: String = ""
    @Published var extraRequirements: String = ""
    @Published var rawResponse: String = ""   // 原始模型返回文本
    @Published var parseMode: String = ""     // 当前解析方式

    var project: Project?
    private var store: ProjectStore?
    private var textService: AITextServiceProtocol?

    func setup(store: ProjectStore, textService: AITextServiceProtocol, project: Project, userTopic: String, extraRequirements: String) {
        self.store = store
        self.textService = textService
        self.project = project
        self.userTopic = userTopic
        self.extraRequirements = extraRequirements
        self.cards = project.copywritingCards.sorted { $0.cardIndex < $1.cardIndex }
        print("📝 [CopyEdit] setup: topic=\(userTopic.prefix(30))..., project=\(project.name)")
        print("📝 [CopyEdit] cards.count=\(cards.count), 非空=\(cards.filter { !$0.isEmpty }.count)")
    }

    // MARK: - 生成文案

    func generateCopy() {
        print("🔵 [CopyEdit] ===== 生成文案 =====")
        guard let ts = textService else {
            errorMessage = "AI 服务未初始化"; print("❌ textService nil"); return
        }
        guard let p = project else {
            errorMessage = "项目未加载"; print("❌ project nil"); return
        }
        let topic = userTopic.trimmingCharacters(in: .whitespaces)
        guard !topic.isEmpty else {
            errorMessage = "选题为空"; print("❌ topic 空"); return
        }

        isLoading = true
        errorMessage = nil
        progressText = "正在生成文案..."
        rawResponse = ""
        parseMode = ""

        print("📝 [CopyEdit] topic=\(topic.prefix(40))")
        print("📝 [CopyEdit] extra=\(extraRequirements.prefix(60))")

        var copyTemplate = AITemplates.load().copywriting
        if let idx = copyTemplate.variables.firstIndex(where: { $0.key == "selected_topic" }) {
            copyTemplate.variables[idx].value = topic
        }
        let systemPrompt = copyTemplate.render()
        print("📝 [CopyEdit] prompt 长度=\(systemPrompt.count)")

        let userMessage = "选题：\(topic)\n图数：\(p.imageCount) 张\n比例：\(p.ratio)\n风格：\(p.ipStyle)\(extraRequirements.isEmpty ? "" : "\n补充要求：\(extraRequirements)")"

        Task {
            do {
                print("⏳ [CopyEdit] 请求 API...")
                let start = Date()
                let r = try await ts.chatCompletion(systemPrompt: systemPrompt, userMessage: userMessage, temperature: 0.8)
                let elapsed = Date().timeIntervalSince(start)
                print("✅ [CopyEdit] 返回 (\(String(format: "%.1f", elapsed))s)")

                // 保存原始响应
                self.rawResponse = r
                print("📥 [CopyEdit] 原始响应长度=\(r.count)")
                print("📥 [CopyEdit] 前200字: \(r.prefix(200))")

                // 解析
                let result = CopywritingParser.parse(rawText: r, expectedCount: p.imageCount)
                self.parseMode = result.mode.rawValue

                if let err = result.error {
                    print("❌ [CopyEdit] 解析失败: \(err)")
                    self.errorMessage = "解析失败：\(err)"
                    self.isLoading = false
                    self.progressText = ""
                    return
                }

                // 更新项目
                var np = p
                np.copywritingCards = result.cards
                if np.status == .draft || np.status == .topicsReady || np.status == .topicSelected {
                    np.status = .copyReady
                }
                self.store?.upsert(np)
                self.project = np
                self.cards = result.cards.sorted { $0.cardIndex < $1.cardIndex }
                self.isLoading = false
                self.progressText = "✅ 文案生成完成（\(result.cards.count)张，\(result.mode.rawValue)）"
                print("✅ [CopyEdit] 完成: \(result.cards.count) 张, 模式=\(result.mode.rawValue)")

            } catch let ne as NetworkError {
                self.errorMessage = "生成失败：[\(ne.category)] \(ne.errorDescription ?? "")"
                self.isLoading = false; self.progressText = ""
                print("❌ [CopyEdit] [\(ne.category)] \(ne.errorDescription ?? "")")
            } catch {
                self.errorMessage = "生成失败：\(error.localizedDescription)"
                self.isLoading = false; self.progressText = ""
                print("❌ [CopyEdit] \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 本地测试（跳过 API，不碰 store）

    func loadMockCopy() {
        print("🧪 [CopyEdit] ===== 加载测试文案(本地) =====")
        isLoading = false
        errorMessage = nil
        rawResponse = ""
        parseMode = "local"

        // 直接构造 6 个 CopywritingCard，零 JSON 零 store
        var mock: [CopywritingCard] = []
        let items: [(Int, String, String, String)] = [
            (0, "你又一次把聊天记录翻到最上面", "原来一个人变心前连标点符号都会变", "钩子，制造代入感"),
            (1, "他说只是加班，你信了", "一个装睡的人叫不醒，但你可以选择先醒", "现实场景，加深共鸣"),
            (2, "领导拍拍你的肩说能者多劳", "能者多劳的下半句是——多劳者未必多得", "放大委屈"),
            (3, "你妈说：不结婚就是不孝", "孝顺不是活成别人想要的样子", "点破本质"),
            (4, "你帮他找了一万种借口", "你值得被明目张胆的偏爱", "开始清醒"),
            (5, "你说没事，然后一个人把委屈咽了回去", "从今天起先照顾好自己，再对世界温柔", "金句收尾"),
        ]
        for (idx, top, bottom, purpose) in items {
            let card = CopywritingCard(cardIndex: idx, topText: top, bottomText: bottom, purpose: purpose)
            print("📝 [CopyEdit]   构造 card[\(idx)] top=\(top.prefix(20))... bottom=\(bottom.prefix(20))...")
            mock.append(card)
        }

        cards = mock
        progressText = "🧪 测试文案 \(mock.count) 张"
        parseMode = "local test"
        print("✅ [CopyEdit] 测试文案就绪: \(cards.count) 张, 不碰 store 不碰 JSON")
    }

    // MARK: - 编辑

    func updateCard(index: Int, topText: String, bottomText: String, purpose: String = "") {
        guard index < cards.count else { return }
        cards[index].topText = topText
        cards[index].bottomText = bottomText
        cards[index].purpose = purpose
        cards[index].isEdited = true
        // 不立即写 store，只在必要时持久化
    }
}
