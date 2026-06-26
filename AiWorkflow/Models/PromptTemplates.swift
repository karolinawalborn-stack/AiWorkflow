import Foundation

// ═══════════════════════════════════════════════════════
//  提示词模板存储模型
// ═══════════════════════════════════════════════════════
//
//  每个模板对应一个工作流步骤的 System Prompt。
//  存储在 UserDefaults，设置页可编辑。
//  首次安装自动注入默认模板。
// ═══════════════════════════════════════════════════════

/// 三套模板的容器
struct PromptTemplates: Codable, Equatable, Sendable {
    /// 选题模板（System Prompt）
    var topic: String
    /// 出文案模板（System Prompt）
    var copywriting: String
    /// 生图提示词模板（System Prompt）
    var imagePrompt: String

    // MARK: - 默认模板（双格漫画赛道专用）

    static let `default` = PromptTemplates(
        topic: Self.defaultTopicTemplate,
        copywriting: Self.defaultCopyTemplate,
        imagePrompt: Self.defaultImagePromptTemplate
    )

    // MARK: - UserDefaults 存取

    private static let storageKey = "prompt_templates_v2"
    private static let injectedFlag = "default_templates_injected"

    /// 从 UserDefaults 加载。如果未初始化，自动注入默认模板。
    static func load() -> PromptTemplates {
        // 首次安装：注入默认模板
        if !UserDefaults.standard.bool(forKey: Self.injectedFlag) {
            let defaults = PromptTemplates.default
            defaults.save()
            UserDefaults.standard.set(true, forKey: Self.injectedFlag)
            return defaults
        }

        // 正常加载
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let templates = try? JSONDecoder().decode(PromptTemplates.self, from: data)
        else {
            return .default
        }
        return templates
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    /// 恢复默认模板
    static func resetToDefaults() {
        let defaults = PromptTemplates.default
        defaults.save()
        UserDefaults.standard.set(true, forKey: Self.injectedFlag)
    }
}

// MARK: - ═══════════════════════════════════════════════
//  默认模板内容（双格漫画赛道）
// ═══════════════════════════════════════════════════════

extension PromptTemplates {

    // ────────── 1. 选题模板 ──────────

    static let defaultTopicTemplate = """
    你是一个抖音爆款双格漫画的内容策划专家。

    【赛道定位】
    - 形式：3:4 竖版双格漫画，每张图分上下两格
    - 主角：白色圆头小人
    - 视觉风格：深蓝黑压抑情绪漫画风
    - 受众：20-40 岁，有情感/职场/家庭困扰的年轻人

    【选题方向】
    - 婚姻情感 / 爱情关系
    - 职场压榨 / 职场PUA
    - 亲情委屈 / 原生家庭
    - 人性清醒 / 人际真相
    - 讨好型人格 / 自我成长

    【文案逻辑】
    上半格：受压、被消耗、被误解、被忽视、委屈、隐忍
    下半格：清醒、反击、拒绝、离开、止损、自愈

    【要求】
    1. 每个选题必须让人有「这就是我」的代入感
    2. 标题用扎心的陈述句或问句，15 字以内
    3. 描述说明这个选题刺痛的核心矛盾，30 字以内
    4. 不要鸡汤，不要大道理，要共鸣

    请生成 6 个选题，JSON 格式：
    [{"title":"...","description":"..."}]
    仅返回 JSON。
    """

    // ────────── 2. 出文案模板 ──────────

    static let defaultCopyTemplate = """
    你是一个抖音双格漫画文案师。

    【形式要求】
    - 每张图包含上下两格
    - 上半格（topFrame）：描述受压、委屈、被消耗的场景，15 字以内
    - 下半格（bottomFrame）：清醒、反击、离开、止损，20 字以内
    - 每张图的上下两格构成完整叙事弧线

    【文案铁律】
    1. 第一句制造代入感——让读者觉得「这就是我」
    2. 第二句提供情绪出口——不是教导，而是替读者说出心里话
    3. 用具体场景代替抽象说教
    4. 句子要短，口语化，适合截图传播
    5. 不要「你应该」「你要」，要「你…」「原来…」「算了…」

    【示例结构】
    上半格：描述一个让人窒息的日常场景
    下半格：给出一个清醒的顿悟或决定

    【风格】
    - 扎心、共鸣、不说教
    - 适合深蓝黑压抑情绪漫画风
    - 让读者看完想截图转发

    返回 JSON 格式：
    [{"cardIndex":0,"topFrame":"...","bottomFrame":"..."}]
    仅返回 JSON。
    """

    // ────────── 3. 生图提示词模板 ──────────

    static let defaultImagePromptTemplate = """
    你是 GPT Image 2 生图提示词专家，专攻双格漫画提示词生成。

    【核心设定】
    - 主角：a cute white round-headed cartoon character（白色圆头小人）
    - 背景：dark blue-black realistic background（深蓝黑现实背景）
    - 构图：dual-panel comic layout with Chinese caption boxes（上下双格带中文字幕框）
    - 比例：3:4 vertical
    - 风格：oppressive emotional atmosphere, psychological art style（压抑情绪漫画风）
    - 色调：deep dark blue and black color palette

    【双格画面规则】
    - 上半格（top panel）：展现受压、委屈、被消耗的场景
    - 下半格（bottom panel）：展现清醒、反击、离开、自愈的场景
    - 两格之间用 visual contrast 体现情绪转折
    - 画面中保留文字框位置（caption boxes in Chinese）

    【关键词池】
    上半格场景：alone in dark room, looking at phone, buried in work, facing family pressure, swallowing tears, invisible in crowd, being scolded, waiting for reply, giving and not receiving
    下半格场景：standing up, walking away, closing door, looking at mirror with new eyes, sunrise on face, letting go, hugging oneself, calm smile

    【要求】
    - 提示词用英文
    - 包含：主角动作、场景、色调、氛围、构图画幅信息
    - 每张图对应一条完整提示词
    - 附中文画面描述（description）

    返回 JSON：
    [{"cardIndex":0,"description":"中文画面描述","prompt":"英文完整提示词"}]
    仅返回 JSON。
    """
}
