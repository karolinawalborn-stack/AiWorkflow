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
    /// 上半格文案
    var topText: String
    /// 下半格文案
    var bottomText: String
    /// 这一张的作用（仅解析器使用，不持久化）
    var purpose: String
    var isEdited: Bool

    init(cardIndex: Int, topText: String = "", bottomText: String = "", purpose: String = "") {
        self.id = UUID()
        self.cardIndex = cardIndex
        self.topText = topText
        self.bottomText = bottomText
        self.purpose = purpose
        self.isEdited = false
    }

    var isEmpty: Bool {
        topText.trimmingCharacters(in: .whitespaces).isEmpty &&
        bottomText.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

// MARK: - 生图提示词状态

enum PromptStatus: String, Codable, Sendable {
    case pending       // 未生成
    case generating    // 生成中
    case success       // 成功写入
    case failed        // API 返回但写入失败
}

// MARK: - 生图提示词（单张卡片一条）

struct PromptCard: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var cardIndex: Int
    /// 最终生图提示词（API 返回的原始文本直接写入，不做复杂解析）
    var promptText: String
    /// API 原始响应
    var rawResponse: String
    /// 当前状态
    var status: PromptStatus
    /// 错误信息（仅 failed 时有值）
    var errorMessage: String?

    init(cardIndex: Int, promptText: String = "", rawResponse: String = "", status: PromptStatus = .pending, errorMessage: String? = nil) {
        self.id = UUID()
        self.cardIndex = cardIndex
        self.promptText = promptText
        self.rawResponse = rawResponse
        self.status = status
        self.errorMessage = errorMessage
    }
}

// MARK: - 图片状态

enum ImageStatus: String, Codable, Sendable {
    case idle              // 未生成
    case generating        // 生成中
    case success           // 成功
    case failed            // 请求失败
    case parseFailed       // 返回成功但解码失败
    case binaryImageReceived // 已收到二进制图片（待保存）
    case taskAccepted      // 接口返回任务 ID（异步）
    case polling           // 正在轮询任务状态
    case saveFailed        // 解码成功但本地保存失败
    case cancelled         // 请求被取消
    case timeout           // 轮询超时
}


// MARK: - 参考图

struct ReferenceImage: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var localFilePath: String
    var fileName: String
    var sortOrder: Int

    init(localFilePath: String, fileName: String = "", sortOrder: Int = 0) {
        self.id = UUID()
        self.localFilePath = localFilePath
        self.fileName = fileName
        self.sortOrder = sortOrder
    }
}

// MARK: - 图片卡片

struct ImageCard: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var cardIndex: Int
    /// 使用的提示词
    var promptText: String
    /// 提交任务时获得的 task_id
    var taskId: String?
    /// 提交任务时获得的文件ID列表
    var efsIds: [String]
    /// 状态
    var status: ImageStatus
    /// API 提交原始响应
    var rawSubmitResponse: String
    /// 查询结果原始响应
    var rawQueryResponse: String
    /// 图片 URL（如有）
    var imageURL: String?
    /// base64 编码的图片数据
    var imageBase64: String?
    /// 本地文件路径（已下载到本地）
    var localFilePath: String?
    /// 单张参考图路径（覆盖全局）
    var referenceImageLocalPath: String?
    /// 错误信息
    var errorMessage: String?

    init(cardIndex: Int, promptText: String = "", taskId: String? = nil, efsIds: [String] = [], status: ImageStatus = .idle, rawSubmitResponse: String = "", rawQueryResponse: String = "", imageURL: String? = nil, imageBase64: String? = nil, localFilePath: String? = nil, referenceImageLocalPath: String? = nil, errorMessage: String? = nil) {
        self.id = UUID()
        self.cardIndex = cardIndex
        self.promptText = promptText
        self.taskId = taskId
        self.efsIds = efsIds
        self.status = status
        self.rawSubmitResponse = rawSubmitResponse
        self.rawQueryResponse = rawQueryResponse
        self.imageURL = imageURL
        self.imageBase64 = imageBase64
        self.localFilePath = localFilePath
        self.errorMessage = errorMessage
    }

    /// 解码后的图片数据（从 base64 或本地文件读取）
    var decodedImageData: Data? {
        if let b64 = imageBase64 { return Data(base64Encoded: b64) }
        if let path = localFilePath { return try? Data(contentsOf: URL(fileURLWithPath: path)) }
        return nil
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

// MARK: - 参考图模式

enum ImageReferenceMode: String, Codable, Sendable, CaseIterable {
    case disabled            = "disabled"
    case url                 = "imageURL"
    case base64              = "base64"
    case multipart           = "multipartUpload"
    case promptOnlyFallback  = "promptOnlyFallback"

    var displayName: String {
        switch self {
        case .disabled:           return "不使用参考图"
        case .url:                return "URL 方式"
        case .base64:             return "Base64 嵌入"
        case .multipart:          return "Multipart 上传"
        case .promptOnlyFallback: return "风格参考（追加到 Prompt）"
        }
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
    var imageCards: [ImageCard]
    var useTemplateID: UUID?

    // 全局参考图
    var globalReferenceImageLocalPath: String?
    var globalReferenceImageMode: ImageReferenceMode
    var useGlobalReferenceImage: Bool
    var referenceImages: [ReferenceImage]
    /// 图片尺寸覆盖（为空则按 ratio 映射）
    var imageSizeOverride: String?

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
    var sortedImages: [ImageCard] { imageCards.sorted { $0.cardIndex < $1.cardIndex } }

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
        self.imageCards = (0..<imageCount).map { ImageCard(cardIndex: $0) }
        self.globalReferenceImageLocalPath = nil
        self.globalReferenceImageMode = .promptOnlyFallback
        self.useGlobalReferenceImage = false
        self.imageSizeOverride = nil
        self.referenceImages = []
    }
}
