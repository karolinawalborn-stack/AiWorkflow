import SwiftUI

@MainActor
final class TopicViewModel: ObservableObject {
    @Published var topics: [TopicCandidate] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedTopicID: UUID?
    @Published var lastDebugLog: String = ""

    var project: Project?
    private var store: ProjectStore?
    private var textService: AITextServiceProtocol?

    func setup(store: ProjectStore, textService: AITextServiceProtocol, project: Project) {
        self.store = store; self.textService = textService; self.project = project
        self.topics = project.sortedTopics
        self.selectedTopicID = project.selectedTopicID
        log("✅ setup: project=\(project.name), textService=\(textService is MockTextService ? "Mock" : "Real"), topics=\(topics.count)")
    }

    // MARK: - 生成选题

    func generateTopics() {
        guard let ts = textService else {
            errorMessage = "AI 服务未初始化"
            log("❌ textService 为 nil")
            return
        }
        isLoading = true; errorMessage = nil
        log("🚀 开始生成选题...")

        let templates = AITemplates.load()
        let systemPrompt = templates.topic.render()
        log("📝 模板长度: \(systemPrompt.count) 字符, 变量: \(templates.topic.variables.count)个")

        Task {
            do {
                log("⏳ 请求 API...")
                let r = try await ts.chatCompletion(systemPrompt: systemPrompt, userMessage: "请生成", temperature: 0.8)
                log("📥 返回: \(r.prefix(100))...")

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
                log("✅ 选题已更新到 UI")
            } catch {
                log("❌ 失败: \(error.localizedDescription)")
                errorMessage = "生成失败：\(error.localizedDescription)"
                isLoading = false
            }
        }
    }

    // MARK: - 测试数据

    func loadMockData() {
        log("🧪 注入测试数据...")
        topics = [
            TopicCandidate(title: "你那么懂事，一定很累吧", description: "总是照顾别人感受的你，有没有问过自己快不快乐", sortOrder: 0),
            TopicCandidate(title: "他回消息越来越慢", description: "从秒回到轮回，一段感情是怎么悄悄死掉的", sortOrder: 1),
            TopicCandidate(title: "月薪八千干了三年没涨过", description: "老实人是怎么被职场一步步榨干的", sortOrder: 2),
            TopicCandidate(title: "你妈说为你好", description: "那些以爱为名的绑架，你还要忍多久", sortOrder: 3),
            TopicCandidate(title: "看清一个人的瞬间", description: "哪一刻你突然发现，这个人其实不值得", sortOrder: 4),
            TopicCandidate(title: "你不是脾气不好，是委屈攒够了", description: "每一次爆发背后，都是积压已久的失望", sortOrder: 5),
        ]
        var p = project!; p.topicCandidates = topics; p.status = .topicsReady
        store?.upsert(p); project = p
        log("✅ 测试数据已加载")
    }

    // MARK: - 选中选题 → 自动创建项目

    func selectTopic(_ topic: TopicCandidate) {
        selectedTopicID = topic.id

        var p = project!
        p.selectedTopicID = topic.id
        // 自动用选题标题作为项目名
        p.name = topic.title
        if p.status == .draft || p.status == .topicsReady { p.status = .topicSelected }
        store?.upsert(p)
        project = p
        log("✅ 选中「\(topic.title)」，项目名已更新")
    }

    // MARK: - 收藏

    func toggleFavorite(_ topic: TopicCandidate) {
        guard let idx = topics.firstIndex(where: { $0.id == topic.id }) else { return }
        topics[idx].isFavorited.toggle()
        var p = project!; p.topicCandidates = topics; store?.upsert(p); project = p
    }

    // MARK: - 日志

    private func log(_ msg: String) { print("[TopicVM] \(msg)"); lastDebugLog = msg }

    // MARK: - JSON 解析

    private func parseJSON(_ text: String) throws -> [(title: String, desc: String)] {
        let d: Data
        if let data = text.data(using: .utf8) { d = data }
        else if let ex = extractJSON(text) { d = ex }
        else { throw NSError(domain: "Parse", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法解析返回数据"]) }
        guard let j = try JSONSerialization.jsonObject(with: d) as? [[String: String]] else {
            log("❌ JSON 格式不对，内容: \((try? String(data: d, encoding: .utf8))?.prefix(200) ?? "N/A")")
            throw NSError(domain: "Parse", code: -1, userInfo: [NSLocalizedDescriptionKey: "数据格式不符"])
        }
        return j.compactMap { guard let t = $0["title"] else { return nil }; return (t, $0["description"] ?? "") }
    }

    private func extractJSON(_ text: String) -> Data? {
        guard let r = text.range(of: "```json"), let e = text[r.upperBound...].range(of: "```") else { return nil }
        return String(text[r.upperBound..<e.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8)
    }
}
