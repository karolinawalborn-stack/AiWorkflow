import SwiftUI

/// 选题 ViewModel——不依赖任何已存在的 Project
///
/// 职责链：
///   生成选题（在内存中）→ 用户选中 → 创建 Project → 返回 projectID
@MainActor
final class TopicViewModel: ObservableObject {
    @Published var topics: [TopicCandidate] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedTopic: TopicCandidate?
    @Published var lastLog: String = ""

    private var textService: AITextServiceProtocol?
    private var store: ProjectStore?

    func setup(textService: AITextServiceProtocol, store: ProjectStore) {
        self.textService = textService
        self.store = store
        log("✅ setup: textService=\(textService is MockTextService ? "Mock" : "Real")")
    }

    // MARK: - 生成选题

    func generateTopics() {
        guard let ts = textService else {
            errorMessage = "AI 服务未初始化"
            log("❌ textService 为 nil")
            return
        }
        isLoading = true
        errorMessage = nil
        log("🚀 生成选题...")

        let templates = AITemplates.load()
        let systemPrompt = templates.topic.render()
        log("📝 模板 \(systemPrompt.count) 字符")

        Task {
            do {
                let r = try await ts.chatCompletion(systemPrompt: systemPrompt, userMessage: "请生成", temperature: 0.8)
                log("📥 返回 \(r.prefix(80))...")

                let parsed = try parseJSON(r)
                topics = parsed.enumerated().map { i, item in
                    TopicCandidate(title: item.title, description: item.desc, sortOrder: i)
                }
                isLoading = false
                log("✅ \(topics.count) 个选题")
            } catch let ne as NetworkError {
                let msg = "[\(ne.category)] \(ne.errorDescription ?? "N/A")"
                errorMessage = "生成失败：\(msg)"
                isLoading = false
                log("❌ \(msg)")
            } catch {
                let msg = "未知错误：\(error.localizedDescription)"
                errorMessage = msg
                isLoading = false
                log("❌ \(msg)")
            }
        }
    }

    // MARK: - 测试数据

    func loadMockData() {
        topics = [
            TopicCandidate(title: "你那么懂事，一定很累吧", description: "总是照顾别人感受的你", sortOrder: 0),
            TopicCandidate(title: "他回消息越来越慢", description: "从秒回到轮回，感情怎么悄悄死掉的", sortOrder: 1),
            TopicCandidate(title: "月薪八千干了三年没涨过", description: "老实人被职场榨干", sortOrder: 2),
            TopicCandidate(title: "你妈说为你好", description: "以爱为名的绑架", sortOrder: 3),
            TopicCandidate(title: "看清一个人的瞬间", description: "哪一刻发现不值得", sortOrder: 4),
            TopicCandidate(title: "你不是脾气不好，是委屈攒够了", description: "每一次爆发都是积压的失望", sortOrder: 5),
        ]
        isLoading = false
        log("🧪 测试数据 \(topics.count) 个")
    }

    // MARK: - 选中选题 → 自动创建 Project

    /// 用户选中一个选题，自动创建 Project，返回 projectID
    func selectTopicAndCreateProject(_ topic: TopicCandidate) -> UUID? {
        guard let store = store else {
            log("❌ store 为 nil，无法创建项目")
            return nil
        }

        selectedTopic = topic

        // 创建 Project，用选题标题作为项目名
        var p = Project(name: topic.title)
        p.topicCandidates = topics
        p.selectedTopicID = topic.id
        p.status = .topicSelected
        store.upsert(p)

        log("✅ 创建项目「\(p.name)」id=\(p.id)")
        return p.id
    }

    // MARK: - 日志

    private func log(_ msg: String) { print("[TopicVM] \(msg)"); lastLog = msg }

    // MARK: - JSON 解析

    private func parseJSON(_ text: String) throws -> [(title: String, desc: String)] {
        let d: Data
        if let data = text.data(using: .utf8) { d = data }
        else if let ex = extractJSON(text) { d = ex }
        else { throw NSError(domain: "Parse", code: -1) }
        guard let j = try JSONSerialization.jsonObject(with: d) as? [[String: String]] else {
            throw NSError(domain: "Parse", code: -1)
        }
        return j.compactMap { guard let t = $0["title"] else { return nil }; return (t, $0["description"] ?? "") }
    }

    private func extractJSON(_ text: String) -> Data? {
        guard let r = text.range(of: "```json"), let e = text[r.upperBound...].range(of: "```") else { return nil }
        return String(text[r.upperBound..<e.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8)
    }
}
