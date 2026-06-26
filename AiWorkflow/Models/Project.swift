import Foundation

// MARK: - 项目生命周期状态

enum ProjectStatus: String, Codable, CaseIterable, Sendable {
    case draft         = "draft"
    case topicsReady   = "topics_ready"
    case topicSelected = "topic_selected"
    case copyReady     = "copy_ready"
    case promptsReady  = "prompts_ready"
    case imagesReady   = "images_ready"
    case completed     = "completed"

    var displayName: String {
        switch self {
        case .draft:         return "草稿"
        case .topicsReady:   return "已生成选题"
        case .topicSelected: return "已选题"
        case .copyReady:     return "文案已出"
        case .promptsReady:  return "提示词已出"
        case .imagesReady:   return "已出图"
        case .completed:     return "已完成"
        }
    }

    var progressValue: Double {
        switch self {
        case .draft:         return 0.0
        case .topicsReady:   return 0.15
        case .topicSelected: return 0.3
        case .copyReady:     return 0.5
        case .promptsReady:  return 0.7
        case .imagesReady:   return 0.9
        case .completed:     return 1.0
        }
    }

    var workflowStep: Int {
        switch self {
        case .draft:         return 0
        case .topicsReady:   return 1
        case .topicSelected: return 1
        case .copyReady:     return 2
        case .promptsReady:  return 3
        case .imagesReady:   return 4
        case .completed:     return 4
        }
    }
}

// MARK: - 选题候选项

struct TopicCandidate: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var topicDescription: String
    var isFavorited: Bool
    var sortOrder: Int

    init(title: String, description: String = "", sortOrder: Int = 0) {
        self.id = UUID()
        self.title = title
        self.topicDescription = description
        self.isFavorited = false
        self.sortOrder = sortOrder
    }
}

// MARK: - 文案卡片（一张图的上半格 + 下半格）

struct CopywritingCard: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var cardIndex: Int
    var topFrame: String        // 上半格：受压/委屈/被消耗
    var bottomFrame: String     // 下半格：清醒/反击/离开
    var isEdited: Bool

    init(cardIndex: Int, topFrame: String = "", bottomFrame: String = "") {
        self.id = UUID()
        self.cardIndex = cardIndex
        self.topFrame = topFrame
        self.bottomFrame = bottomFrame
        self.isEdited = false
    }

    var isEmpty: Bool {
        topFrame.trimmingCharacters(in: .whitespaces).isEmpty &&
        bottomFrame.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

// MARK: - 生图提示词

struct PromptCard: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var cardIndex: Int
    var prompt: String
    var imageDescription: String

    init(cardIndex: Int, prompt: String = "", imageDescription: String = "") {
        self.id = UUID()
        self.cardIndex = cardIndex
        self.prompt = prompt
        self.imageDescription = imageDescription
    }
}

// MARK: - 已生成图片

struct GeneratedImageItem: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var cardIndex: Int
    var isGenerated: Bool
    var imageDataBase64: String?
    var localPath: String?
    var usedPrompt: String?
    var createdAt: Date

    init(cardIndex: Int) {
        self.id = UUID()
        self.cardIndex = cardIndex
        self.isGenerated = false
        self.createdAt = Date()
    }

    var imageData: Data? {
        get { imageDataBase64.flatMap { Data(base64Encoded: $0) } }
        set { imageDataBase64 = newValue?.base64EncodedString() }
    }
}

// MARK: - 提示词模板（旧版存储结构，保留兼容）

struct SavedTemplate: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var content: String
    var createdAt: Date

    init(name: String, content: String) {
        self.id = UUID()
        self.name = name
        self.content = content
        self.createdAt = Date()
    }
}

// MARK: - 项目（自包含聚合根）

struct Project: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var category: String
    var style: String
    var imageCount: Int
    var ratio: String
    var ipStyle: String
    var statusRaw: String
    var createdAt: Date
    var updatedAt: Date

    // 工作流数据（全部内嵌）
    var topicCandidates: [TopicCandidate]
    var selectedTopicID: UUID?
    var copywritingCards: [CopywritingCard]
    var promptCards: [PromptCard]
    var imageItems: [GeneratedImageItem]
    var useTemplateID: UUID?

    var status: ProjectStatus {
        get { ProjectStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    var selectedTopic: TopicCandidate? {
        guard let id = selectedTopicID else { return nil }
        return topicCandidates.first { $0.id == id }
    }

    var sortedTopics: [TopicCandidate] { topicCandidates.sorted { $0.sortOrder < $1.sortOrder } }
    var sortedCopyCards: [CopywritingCard] { copywritingCards.sorted { $0.cardIndex < $1.cardIndex } }
    var sortedPrompts: [PromptCard] { promptCards.sorted { $0.cardIndex < $1.cardIndex } }
    var sortedImages: [GeneratedImageItem] { imageItems.sorted { $0.cardIndex < $1.cardIndex } }

    init(
        name: String,
        category: String = "双格漫画",
        style: String = "深蓝黑压抑情绪漫画",
        imageCount: Int = 6,
        ratio: String = "3:4",
        ipStyle: String = "白色圆头小人，深蓝黑背景，压抑情绪风格"
    ) {
        self.id = UUID()
        self.name = name
        self.category = category
        self.style = style
        self.imageCount = imageCount
        self.ratio = ratio
        self.ipStyle = ipStyle
        self.statusRaw = ProjectStatus.draft.rawValue
        self.createdAt = Date()
        self.updatedAt = Date()
        self.topicCandidates = []
        self.selectedTopicID = nil
        self.useTemplateID = nil
        self.copywritingCards = (0..<imageCount).map { CopywritingCard(cardIndex: $0) }
        self.promptCards = (0..<imageCount).map { PromptCard(cardIndex: $0) }
        self.imageItems = (0..<imageCount).map { GeneratedImageItem(cardIndex: $0) }
    }
}
