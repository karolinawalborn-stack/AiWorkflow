import SwiftUI
import OSLog

@MainActor
final class TopicViewModel: ObservableObject {
    @Published var topics: [TopicCandidate] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var positioningInput: String = ""
    @Published var selectedTopicID: UUID?
    @Published var lastDebugLog: String = ""

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
        log("✅ setup() 完成. textService=\(textService is MockTextService ? "Mock" : "Real"), topics=\(topics.count)个")
    }

    // MARK: - 生成选题

    func generateTopics() {
        guard !positioningInput.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "请输入账号定位"; log("❌ 定位为空"); return
        }
        guard let ts = textService else {
            errorMessage = "AI 服务未初始化（textService 为 nil），请在设置页检查 API 配置"
            log("❌ textService 为 nil！setup() 可能未被调用")
            return
        }

        isLoading = true; errorMessage = nil
        log("🚀 开始生成选题... positioningInput=\(positioningInput.prefix(30))...")

        let systemPrompt = AITemplates.load().topic.render()
        log("📝 System Prompt 长度: \(systemPrompt.count) 字符")

        Task {
            do {
                log("⏳ 正在请求 API... model=\(ts is MockTextService ? "Mock" : "InternalToolStation")")
                let r = try await ts.chatCompletion(systemPrompt: systemPrompt, userMessage: positioningInput, temperature: 0.8)
                log("📥 API 返回原始文本: \(r.prefix(200))...")

                let parsed = try parseJSON(r)
                log("✅ 解析成功: \(parsed.count) 个选题")

                var p = project!
                p.topicCandidates = parsed.enumerated().map { i, item in
                    TopicCandidate(title: item.title, description: item.desc, sortOrder: i)
                }
                p.status = .topicsReady
                store?.upsert(p); project = p
                topics = p.sortedTopics
                isLoading = false
                log("✅ 选题已更新到 UI, topics=\(topics.count)个")
            } catch let error as DecodingError {
                log("❌ JSON 解析失败: \(error.localizedDescription)")
                errorMessage = "数据解析失败，AI 返回格式异常，请重试"
                isLoading = false
            } catch {
                log("❌ 生成失败: \(error.localizedDescription)")
                errorMessage = "生成失败：\(error.localizedDescription)"
                isLoading = false
            }
        }
    }

    // MARK: - 加载测试数据（区分 UI 问题和接口问题）

    func loadMockData() {
        log("🧪 注入测试选题数据...")
        isLoading = false; errorMessage = nil
        topics = [
            TopicCandidate(title: "你那么懂事，一定很累吧", description: "总是照顾别人感受的你，有没有问过自己快不快乐", sortOrder: 0),
            TopicCandidate(title: "他回消息越来越慢", description: "从秒回到轮回，一段感情是怎么悄悄死掉的", sortOrder: 1),
            TopicCandidate(title: "月薪八千干了三年没涨过", description: "老实人是怎么被职场一步步榨干的", sortOrder: 2),
            TopicCandidate(title: "你妈说为你好", description: "那些以爱为名的绑架，你还要忍多久", sortOrder: 3),
            TopicCandidate(title: "看清一个人的瞬间", description: "哪一刻你突然发现，这个人其实不值得", sortOrder: 4),
            TopicCandidate(title: "你不是脾气不好，是委屈攒够了", description: "每一次爆发背后，都是积压已久的失望", sortOrder: 5),
        ]
        log("✅ 测试选题已加载: \(topics.count) 个")
    }

    // MARK: - 其他

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
        log("✅ 选中选题: \(topic.title)")
    }

    // MARK: - 日志

    private func log(_ msg: String) {
        print("[TopicVM] \(msg)")
        lastDebugLog = msg
    }

    // MARK: - JSON 解析

    private func parseJSON(_ text: String) throws -> [(title: String, desc: String)] {
        let d: Data
        if let data = text.data(using: .utf8) { d = data }
        else if let ex = extractJSON(text) { d = ex }
        else {
            log("❌ 无法从响应中提取 JSON")
            throw NSError(domain: "Parse", code: -1, userInfo: [NSLocalizedDescriptionKey: "API 返回格式异常，无法解析"])
        }

        guard let j = try JSONSerialization.jsonObject(with: d) as? [[String: String]] else {
            log("❌ JSON 结构不是 [[String:String]] 类型")
            if let raw = String(data: d, encoding: .utf8) { log("📄 原始 JSON: \(raw.prefix(300))") }
            throw NSError(domain: "Parse", code: -1, userInfo: [NSLocalizedDescriptionKey: "返回数据格式不符"])
        }
        return j.compactMap { guard let t = $0["title"] else { return nil }; return (t, $0["description"] ?? "") }
    }

    private func extractJSON(_ text: String) -> Data? {
        guard let r = text.range(of: "```json"), let e = text[r.upperBound...].range(of: "```") else { return nil }
        return String(text[r.upperBound..<e.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8)
    }
}
