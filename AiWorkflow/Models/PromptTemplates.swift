import Foundation

// ═══════════════════════════════════════════════════════
//  可编辑模板系统
// ═══════════════════════════════════════════════════════
//
//  数据结构：
//    AITemplate          ← 一套模板（正文 + 变量列表）
//    ├── body: String        ← 模板正文，含 {{variable}} 占位符
//    └── variables: []       ← 变量列表
//         ├── key            ← 变量名（对应 {{key}}）
//         ├── label          ← 显示名
//         └── value          ← 当前值
//
//  AITemplates           ← 三套模板的容器
//  AITemplateRenderer    ← 渲染器：{{key}} → value
//
//  设置页可以看到和编辑：
//  1. 模板正文（TextEditor）
//  2. 变量列表（key-value 对）
//  3. 最终 prompt 预览
//  4. 恢复默认按钮
// ═══════════════════════════════════════════════════════

// MARK: - 单个变量

struct AITemplateVariable: Codable, Equatable, Sendable, Identifiable {
    var id: String { key }
    let key: String
    var label: String
    var value: String
    let defaultValue: String

    init(key: String, label: String, value: String, defaultValue: String? = nil) {
        self.key = key
        self.label = label
        self.value = value
        self.defaultValue = defaultValue ?? value
    }
}

// MARK: - 单套模板

struct AITemplate: Codable, Equatable, Sendable {
    let id: String
    var name: String
    var body: String
    var variables: [AITemplateVariable]
    let defaultBody: String
    let defaultVariables: [AITemplateVariable]

    init(id: String, name: String, body: String, variables: [AITemplateVariable]) {
        self.id = id
        self.name = name
        self.body = body
        self.variables = variables
        self.defaultBody = body
        self.defaultVariables = variables
    }

    /// 渲染最终 prompt（替换所有 {{key}}）
    func render() -> String {
        var result = body
        for v in variables {
            result = result.replacingOccurrences(of: "{{\(v.key)}}", with: v.value)
        }
        return result
    }

    /// 恢复默认正文
    func resetBody() -> AITemplate {
        var t = self
        t.body = defaultBody
        return t
    }

    /// 恢复默认变量
    func resetVariables() -> AITemplate {
        var t = self
        t.variables = defaultVariables.map { AITemplateVariable(key: $0.key, label: $0.label, value: $0.defaultValue, defaultValue: $0.defaultValue) }
        return t
    }
}

// MARK: - 三套模板容器

struct AITemplates: Codable, Equatable, Sendable {
    var topic: AITemplate
    var copywriting: AITemplate
    var imagePrompt: AITemplate
}

// MARK: - 渲染器

struct AITemplateRenderer {
    /// 渲染指定模板
    static func render(_ template: AITemplate) -> String {
        template.render()
    }

    /// 渲染并打印调试信息
    static func debugRender(_ template: AITemplate) -> String {
        let result = template.render()
        print("[TemplateRenderer] 渲染 \(template.name):")
        print("[TemplateRenderer] 正文长度: \(template.body.count) 字符")
        print("[TemplateRenderer] 变量数: \(template.variables.count)")
        for v in template.variables {
            print("[TemplateRenderer]   {{\(v.key)}} = \(v.value.prefix(50))...")
        }
        return result
    }
}

// MARK: - 默认模板

extension AITemplates {
    static let `default`: AITemplates = {
        AITemplates(
            topic: AITemplate(
                id: "topic",
                name: "选题模板",
                body: defaultTopicBody,
                variables: defaultTopicVariables
            ),
            copywriting: AITemplate(
                id: "copywriting",
                name: "文案模板",
                body: defaultCopyBody,
                variables: defaultCopyVariables
            ),
            imagePrompt: AITemplate(
                id: "imagePrompt",
                name: "生图提示词模板",
                body: defaultImagePromptBody,
                variables: defaultImagePromptVariables
            )
        )
    }()
}

// MARK: - UserDefaults 存取

extension AITemplates {
    private static let storageKey = "prompt_templates_v3"
    private static let injectedFlag = "prompt_templates_v3_injected"

    static func load() -> AITemplates {
        if !UserDefaults.standard.bool(forKey: Self.injectedFlag) {
            let defaults = AITemplates.default
            defaults.save()
            UserDefaults.standard.set(true, forKey: Self.injectedFlag)
            return defaults
        }
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let templates = try? JSONDecoder().decode(AITemplates.self, from: data)
        else { return .default }
        return templates
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    static func resetToDefaults() {
        let defaults = AITemplates.default
        defaults.save()
        UserDefaults.standard.set(true, forKey: Self.injectedFlag)
    }
}

// MARK: - ═══════════════════════════════════════════════
//  模板正文（含 {{variable}} 占位符）
// ═══════════════════════════════════════════════════════

extension AITemplates {

    // ────────── 1. 选题模板正文 ──────────

    static let defaultTopicBody = """
你现在是一个抖音爆款情绪图文账号的选题策划专家，请围绕"{{account_style}}"这个账号定位，帮我策划适合做成{{topic_count}}张图一组的爆款选题。

我的内容形式是：
{{format}}

账号风格要求：
{{account_tone}}

选题方向优先围绕：
{{topic_directions}}

选题要求：
{{requirements}}

请输出 50 个选题，并按以下格式输出：

【选题标题】
【适合方向】爱情/婚姻/亲情/职场/人性/讨好型人格
【核心痛点】
【最适合的高爆场景模板】例如：餐桌羞辱→门口离开 / 办公室压榨→会议室拍桌 / 客厅指责→门口反击
【为什么适合做成 5-6 张图】
【6张图的内容递进】
- 第1张：钩子
- 第2张：现实场景
- 第3张：委屈加深
- 第4张：点破本质
- 第5张：开始清醒
- 第6张：金句收尾
【为什么容易爆】

最后请再额外输出：
1. 最容易爆的 10 个选题
2. 最适合长期做的 10 个选题
3. 最适合起号的 10 个选题
4. 最值得优先做的前 5 个选题，并说明原因
"""

    static let defaultTopicVariables: [AITemplateVariable] = [
        AITemplateVariable(key: "account_style", label: "账号风格定位", value: "成年人关系清醒 + 人性认知 + 情绪反转"),
        AITemplateVariable(key: "topic_count", label: "每组图数", value: "5-6"),
        AITemplateVariable(key: "format", label: "内容形式", value: "- 一个作品由 5-6 张图组成\n- 每张图比例为 3:4 竖版\n- 每张图内部为上下双格漫画\n- 上半格偏委屈、压抑、被误解、被消耗、被否定、被针对\n- 下半格偏清醒、反击、觉醒、离开、拒绝、翻脸、止损\n- 图片里会直接带文案字幕框\n- 内容适合抖音图文轮播发布"),
        AITemplateVariable(key: "account_tone", label: "账号风格", value: "- 扎心\n- 现实\n- 清醒\n- 克制\n- 锋利\n- 强共鸣\n- 强传播\n- 一眼能懂\n- 适合 25-45 岁成年人"),
        AITemplateVariable(key: "topic_directions", label: "选题方向", value: "1. 爱情与婚姻清醒\n2. 亲情与原生家庭委屈\n3. 职场压榨与反击\n4. 讨好型人格与边界感\n5. 人性真相与关系本质\n6. 女性成长与清醒离场"),
        AITemplateVariable(key: "requirements", label: "选题要求", value: "1. 每个选题都必须适合拆成 5-6 张图，不是一句话就讲完。\n2. 每个选题都必须自带明显冲突，天然适合「上半格受压、下半格反转」的结构。\n3. 每个选题都必须有现实场景感，比如餐桌、客厅、门口、卧室、办公室、会议室、走廊等。\n4. 每个选题都要适合做成「情绪短剧封面感」的双格漫画，而不是空泛鸡汤。\n5. 优先给我容易爆、容易持续、更适合批量连更的选题。\n6. 不要太文艺，不要太哲学，不要过于小众，不要只有情绪没有观点。"),
    ]

    // ────────── 2. 文案模板正文 ──────────

    static let defaultCopyBody = """
你现在是一个抖音爆款双格漫画文案策划专家，请围绕我给出的选题，创作一组适合 {{image_count}} 张图发布的上下双格漫画文案。

我的内容形式是：
{{format}}

账号定位：
{{account_positioning}}

文案要求：
{{copy_requirements}}

请按以下格式输出：

【选题】
{{selected_topic}}

【内容方向判断】
自动判断这个题更适合做成：婚姻情感 / 爱情关系 / 职场压榨 / 亲情委屈 / 人性清醒 / 讨好型人格

【封面标题】
给我 5 个适合抖音封面的标题，要求短、狠、扎心、容易点开。

【6张双格文案】
第1张
- 上半格文案：
- 下半格文案：
- 这一张的作用：

第2张
- 上半格文案：
- 下半格文案：
- 这一张的作用：

第3张
- 上半格文案：
- 下半格文案：
- 这一张的作用：

第4张
- 上半格文案：
- 下半格文案：
- 这一张的作用：

第5张
- 上半格文案：
- 下半格文案：
- 这一张的作用：

第6张
- 上半格文案：
- 下半格文案：
- 这一张的作用：

【整组内容核心观点】
用一句话总结这组内容最扎心的核心。

【发布文案】
再写 3 条适合发抖音时配在作品下方的发布文案，每条 40-80 字，带一点共鸣感和互动感，但不要太营销。

【评论区引导】
再写 5 条适合引导评论和共鸣的短句。

【文案自检】
请检查这 6 张图的文案是否：
- 足够短
- 足够扎心
- 足够适合图内直接生成
- 有明显递进
- 有明显反差
如果不够，请自动优化后再给最终版本。

我这次的选题是：
"{{selected_topic}}"
"""

    static let defaultCopyVariables: [AITemplateVariable] = [
        AITemplateVariable(key: "image_count", label: "每组图数", value: "6"),
        AITemplateVariable(key: "selected_topic", label: "当前选题", value: "待生成"),
        AITemplateVariable(key: "format", label: "内容形式", value: "- 一个作品共 6 张图\n- 每张图比例为 3:4 竖版\n- 每张图内部为上下双格\n- 图片里直接带文案字幕框\n- 所以每个半格文案必须短、狠、清晰、适合直接上图"),
        AITemplateVariable(key: "account_positioning", label: "账号定位", value: "- 成年人关系清醒\n- 人性认知\n- 情绪反转\n- 扎心、现实、通透、克制、锋利\n- 适合抖音图文轮播爆款内容"),
        AITemplateVariable(key: "copy_requirements", label: "文案要求", value: "1. 一共输出 6 张图，每张图都包含上下半格文案和这一张的作用\n2. 6 张图整体必须有明显递进：钩子→场景→委屈加深→点破本质→开始清醒→金句收尾\n3. 每张图内部必须有反差：上半格受压，下半格反击\n4. 每个半格文案控制在 6-12 个字，尽量不超过 14 个字\n5. 文案必须短句化、结论化、适合直接生成在图片里\n6. 不要写成长段散文，不要空泛鸡汤，不要过度抒情\n7. 文案要让用户有「这说的不就是我」的感觉\n8. 优先生成更容易爆的表达"),
    ]

    // ────────── 3. 生图提示词模板正文 ──────────

    static let defaultImagePromptBody = """
你现在是一个专门为 GPT Image 2 服务的"抖音爆款双格漫画导演级生图提示词专家"。

你的任务是：
当我只给你"上半格文案"和"下半格文案"时，你必须先在内部自动完成以下步骤，再输出一条可直接复制给 GPT Image 2 的最终中文生图提示词：
1. 自动判断这组文案最适合的内容方向
2. 自动匹配最容易爆的现实冲突场景
3. 自动补足人物关系、动作、道具、灯光、站位、情绪反差
4. 自动选择最有传播感的戏剧瞬间
5. 自动优化字幕呈现方式，避免书面腔、避免结尾标点、避免排版难看
6. 自动固定为"{{page_style}}"的标准双格漫画页版式
7. 最终只输出一条完整成品提示词

【重要规则】
- 我不需要手动提供方向、场景、要求
- 如果我没写，你必须自动补全
- 你不要问我问题，直接给我最优解
- 你的输出目标不是"正确生成一张图"，而是"生成一张更像抖音爆款封面的双格戏剧漫画图"
- 你输出的内容必须可直接复制给 GPT Image 2 使用
- 不要输出分析过程，不要解释，不要多版本

【图片形式】
- 比例固定为 {{image_ratio}} 竖版
- 单张图
- 图内为上下双格漫画结构
- 整张图采用"{{page_style}}"的标准双格漫画页版式
- 外围白色留白边框必须完整可见
- 中间白色留白分隔边框必须完整可见

【成片风格】
{{visual_style}}

【人物设定】
{{character_setting}}

【自动判断方向规则】
{{direction_rules}}

【自动选场景规则】
{{scene_rules}}

【分镜设计原则】
{{frame_design_rules}}

【爆点强制要求】
每张图必须至少包含以下元素中的 3 个：
{{explosion_elements}}

【文案与画面关系】
- 文案不是装饰，必须和动作强绑定
- 上半格文案要对应"受压瞬间"
- 下半格文案要对应"反转瞬间"
- 如果文案抽象，你要自动把它翻译成最具体、最容易爆的生活冲突场景

【字幕要求】
- 图片里直接生成文字
- 每个分镜底部中央都放一个白色圆角矩形字幕框
- 上半格字幕内容必须完全等于我给的上半格文案：{{top_caption}}
- 下半格字幕内容必须完全等于我给的下半格文案：{{bottom_caption}}
- 文字尽量单行显示，中文清晰、工整、居中排版
- 字幕框统一样式，不遮挡人物主要动作和表情
- 默认不添加任何结尾标点符号
- 如果我给出的文案里自带标点，请自动去掉标点后再用于图片字幕

【构图要求】
- 适合 {{image_ratio}} 手机轮播图观看
- 主体足够大，人物不要太小
- 每格都要有清晰视觉中心
- 画面要像"情绪短剧封面"
- 保证字幕框与主体动作不打架

【参考图规则】
若我上传参考图，则参考其分镜节奏、色调、人物关系、字幕框样式，不复制具体人物身份和五官。

【输出规则】
你只输出一段可直接复制给 GPT Image 2 的最终中文生图提示词。不要解释，不要分析，不要多版本。

【默认负面限制】
{{negative_restrictions}}

【我的输入格式】
【上半格】文案：{{top_caption}}
【下半格】文案：{{bottom_caption}}
可选附加项：{{extra_requirements}}

你收到后，直接生成最终生图提示词。
"""

    static let defaultImagePromptVariables: [AITemplateVariable] = [
        AITemplateVariable(key: "image_ratio", label: "图片比例", value: "3:4"),
        AITemplateVariable(key: "page_style", label: "版式风格", value: "细白留白边框"),
        AITemplateVariable(key: "visual_style", label: "成片风格", value: "- 只采用深蓝黑压抑情绪漫画路线\n- 冷蓝黑色调，局部高光\n- 手绘漫画 + graphic novel 质感\n- 钢笔排线，强阴影，电影级打光\n- 情绪压抑，构图戏剧化，环境真实\n- 不要做成纯观点海报/极简贴纸图/轻松可爱风/低幼卡通风"),
        AITemplateVariable(key: "character_setting", label: "人物设定", value: "- 主角固定为极简白色圆头小人，头大身细，五官极简，但表情和肢体必须清晰有情绪\n- 配角为半写实成年人，五官清晰，姿态自然，但压迫感强\n- 上下两格主角必须是同一形象\n- 尽量保持一强一弱的人物关系表达：一站一坐、一近一远、一亮一暗、一动一静"),
        AITemplateVariable(key: "direction_rules", label: "方向判断规则", value: "1. 心软/懂事/善良/厚道/重情重义/总退让 → 婚姻情感/爱情关系/人性清醒/讨好型人格\n2. 工作能力强/能干/负责/加班/忍让/背锅 → 职场压榨/职场反击\n3. 父母/家里/亲人/偏心/懂事的孩子/受委屈 → 亲情关系/原生家庭\n4. 抽象的 → 自动选最适合先受压再反转的方向"),
        AITemplateVariable(key: "scene_rules", label: "场景规则", value: "1. 餐桌羞辱→门口离开（婚姻/情感/失望）\n2. 客厅指责→门口反击（善良/厚道/隐忍/翻脸）\n3. 办公室压榨→会议室拍桌（工作能力强/老实/背锅）\n4. 深夜冷暴力→收拾行李离开（婚姻失望/彻底死心）\n5. 家庭偏心→起身离席（亲情委屈/不被理解）\n6. 被利用被消耗→当场止损（重情重义/心软/善良）"),
        AITemplateVariable(key: "frame_design_rules", label: "分镜设计原则", value: "- 上半格必须表现被压制、被羞辱、被忽视、被误解的具体瞬间\n- 下半格必须表现翻脸、离开、反击、拒绝、转身的具体瞬间\n- 下半格的冲击力必须明显强于上半格\n- 优先选最容易一眼看懂的瞬间，而不是完整叙事"),
        AITemplateVariable(key: "explosion_elements", label: "爆点要素", value: "- 强动作：指责、拍桌、倒酒、甩文件、拖行李箱、开门离开、站起反击\n- 强道具：礼物盒、红酒、文件堆、行李箱、门外强光、空酒杯、散落餐具\n- 强站位：一站一坐、一近一远、一亮一暗、一动一静\n- 强灯光：门口逆光、头顶单灯、桌面烛光、侧面冷光\n- 强残局：散落文件、打翻椅子、餐桌凌乱、地面碎片"),
        AITemplateVariable(key: "negative_restrictions", label: "负面限制", value: "不要：文字乱码、中文错字、英文替代中文、手写体、水印、logo、签名、Q版萌系、低幼卡通风、暖色调、高饱和配色、血腥暴力、恐怖元素、畸形手脚、扭曲五官、模糊人脸、杂乱背景、主体太小、构图失衡、动作平淡、情绪不明确、场景空洞、没有白色外边框、没有中间分隔边框、白边过厚或过细、黑色边框、纯黑分隔线、画面贴满外缘"),
        AITemplateVariable(key: "top_caption", label: "上半格文案（自动替换）", value: "待输入"),
        AITemplateVariable(key: "bottom_caption", label: "下半格文案（自动替换）", value: "待输入"),
        AITemplateVariable(key: "extra_requirements", label: "补充要求", value: "无"),
    ]
}
