import SwiftUI

@MainActor
final class CopyEditViewModel: ObservableObject {
    @Published var cards: [CopywritingCard] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var progressText: String = ""
    @Published var userTopic: String = ""
    @Published var extraRequirements: String = ""

    var project: Project?
    private var store: ProjectStore?
    private var textService: AITextServiceProtocol?

    func setup(store: ProjectStore, textService: AITextServiceProtocol, project: Project, userTopic: String, extraRequirements: String) {
        self.store = store; self.textService = textService; self.project = project
        self.userTopic = userTopic
        self.extraRequirements = extraRequirements
        self.cards = project.sortedCopyCards
        print("📝 CopyEditVM.setup: topic=\(userTopic.prefix(30))..., cards=\(cards.count)")
    }

    func generateCopy() {
        print("🔵 [CopyEdit] generateCopy() 被调用")
        guard let ts = textService else {
            errorMessage = "AI 服务未初始化（textService 为 nil）"
            print("❌ [CopyEdit] textService 为 nil")
            return
        }
        guard let p = project else {
            errorMessage = "项目数据未加载"
            print("❌ [CopyEdit] project 为 nil")
            return
        }
        let topic = userTopic.trimmingCharacters(in: .whitespaces)
        guard !topic.isEmpty else {
            errorMessage = "选题为空，请在开始创作页输入选题"
            print("❌ [CopyEdit] userTopic 为空")
            return
        }

        isLoading = true; errorMessage = nil; progressText = "正在生成文案..."
        print("📝 [CopyEdit] 选题: \(topic.prefix(40))")
        print("📝 [CopyEdit] 补充要求: \(extraRequirements.prefix(60))")
        print("📝 [CopyEdit] project: \(p.name) id=\(p.id)")

        // 使用文案模板，注入选题
        var copyTemplate = AITemplates.load().copywriting
        print("📝 [CopyEdit] 模板正文长度: \(copyTemplate.body.count)")
        if let idx = copyTemplate.variables.firstIndex(where: { $0.key == "selected_topic" }) {
            copyTemplate.variables[idx].value = topic
            print("📝 [CopyEdit] 注入 selected_topic = \(topic.prefix(30))")
        }
        let systemPrompt = copyTemplate.render()
        print("📝 [CopyEdit] 最终 prompt 前 200 字: \(systemPrompt.prefix(200))")

        let userMessage = "选题：\(topic)\n图数：\(p.imageCount) 张\n比例：\(p.ratio)\n风格：\(p.ipStyle)\(extraRequirements.isEmpty ? "" : "\n补充要求：\(extraRequirements)")"
        let startTime = Date()

        Task {
            do {
                print("⏳ [CopyEdit] 请求开始... model=\(ts is MockTextService ? "Mock" : "Real")")
                let r = try await ts.chatCompletion(systemPrompt: systemPrompt, userMessage: userMessage, temperature: 0.8)
                let elapsed = Date().timeIntervalSince(startTime)
                print("✅ [CopyEdit] API 返回 (\(String(format: "%.1f", elapsed))s)")
                print("📥 [CopyEdit] 原始响应: \(r.prefix(300))")

                let parsed = try parseCopyJSON(r)
                print("✅ [CopyEdit] 解析成功: \(parsed.count) 条文案")

                var np = p
                var nc = np.copywritingCards
                for item in parsed where item.index < nc.count {
                    nc[item.index].topFrame = item.top
                    nc[item.index].bottomFrame = item.bottom
                }
                np.copywritingCards = nc
                if np.status == .draft || np.status == .topicsReady || np.status == .topicSelected { np.status = .copyReady }
                store?.upsert(np); project = np
                cards = nc.sorted { $0.cardIndex < $1.cardIndex }
                isLoading = false; progressText = "✅ 文案生成完成"
                print("✅ [CopyEdit] 文案已更新到 UI: \(cards.count) 张")
            } catch let ne as NetworkError {
                let msg = "[\(ne.category)] \(ne.errorDescription ?? "")"
                errorMessage = "生成失败：\(msg)"
                isLoading = false; progressText = ""
                print("❌ [CopyEdit] \(msg)")
            } catch {
                let msg = "未知错误：\(error.localizedDescription)"
                errorMessage = msg
                isLoading = false; progressText = ""
                print("❌ [CopyEdit] \(msg)")
            }
        }
    }

    /// 加载本地测试文案（跳过 API）
    func loadMockCopy() {
        print("🧪 [CopyEdit] 加载测试文案")
        isLoading = false; errorMessage = nil
        cards = [
            CopywritingCard(cardIndex: 0, topFrame: "你又一次把聊天记录翻到最上面", bottomFrame: "原来一个人变心前连标点符号都会变"),
            CopywritingCard(cardIndex: 1, topFrame: "他说只是加班，你信了", bottomFrame: "一个装睡的人叫不醒，但你可以选择先醒"),
            CopywritingCard(cardIndex: 2, topFrame: "领导拍拍你的肩说能者多劳", bottomFrame: "能者多劳的下半句是——多劳者未必多得"),
            CopywritingCard(cardIndex: 3, topFrame: "你妈说：不结婚就是不孝", bottomFrame: "孝顺不是活成别人想要的样子"),
            CopywritingCard(cardIndex: 4, topFrame: "你帮他找了一万种借口", bottomFrame: "你值得被明目张胆的偏爱"),
            CopywritingCard(cardIndex: 5, topFrame: "你说没事，然后一个人把委屈咽了回去", bottomFrame: "从今天起先照顾好自己，再对世界温柔"),
        ]
        if var p = project { p.copywritingCards = cards; store?.upsert(p); project = p }
        progressText = "🧪 测试文案已加载"
        print("✅ [CopyEdit] 测试文案已加载: \(cards.count) 张")
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
