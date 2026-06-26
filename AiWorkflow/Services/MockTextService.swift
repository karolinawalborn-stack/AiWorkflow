import Foundation

/// Mock 文本服务——不依赖任何 API
final class MockTextService: AITextServiceProtocol {
    func chatCompletion(systemPrompt: String, userMessage: String, temperature: Double) async throws -> String {
        try await Task.sleep(nanoseconds: 1_000_000_000)

        if systemPrompt.contains("选题") { return Self.mockTopics }
        if systemPrompt.contains("文案") || systemPrompt.contains("双格") { return Self.mockCopy }
        if systemPrompt.contains("提示词") || systemPrompt.contains("生图") { return Self.mockPrompts }
        return "mock ok"
    }

    static let mockTopics = """
    [{"title":"你那么懂事，一定很累吧","description":"总是照顾别人感受的你，有没有问过自己快不快乐"},{"title":"他回消息越来越慢","description":"从秒回到轮回，一段感情是怎么悄悄死掉的"},{"title":"月薪八千干了三年没涨过","description":"老实人是怎么被职场一步步榨干的"},{"title":"你妈说为你好","description":"那些以爱为名的绑架，你还要忍多久"},{"title":"看清一个人的瞬间","description":"哪一刻你突然发现，这个人其实不值得"},{"title":"你不是脾气不好，是委屈攒够了","description":"每一次爆发背后，都是积压已久的失望"}]
    """

    static let mockCopy = """
    [{"cardIndex":0,"topFrame":"你又一次把聊天记录翻到最上面，想看看他最开始是怎么叫你的。","bottomFrame":"原来一个人变心前，连标点符号都会变。你该把这份温柔留给自己了。"},{"cardIndex":1,"topFrame":"他说只是加班，你信了。可是这个月他已经加了三十二天班了。","bottomFrame":"你不是傻，你只是不想承认——一个装睡的人，叫不醒，但你可以选择先醒。"},{"cardIndex":2,"topFrame":"领导拍拍你的肩说能者多劳，于是同事的活全变成了你的活。","bottomFrame":"能者多劳的下半句是——多劳者，未必多得。你的善良应该有底线。"},{"cardIndex":3,"topFrame":"你妈说：不结婚就是不孝。这句话从你25岁听到了35岁。","bottomFrame":"孝顺不是活成别人想要的样子，而是有勇气活成自己。"},{"cardIndex":4,"topFrame":"你帮他找了一万种借口，其实真相只有一个——他没你想象中那么在乎。","bottomFrame":"别再帮他找理由了，你值得被明目张胆的偏爱，而不是遮遮掩掩的凑合。"},{"cardIndex":5,"topFrame":"你说没事，然后一个人把委屈咽了回去。这是你今天第三次说没事了。","bottomFrame":"懂事不是你的天赋，是你受过伤的证明。从今天起，先照顾好自己，再对世界温柔。"}]
    """

    static let mockPrompts = """
    [{"cardIndex":0,"description":"白色圆头小人深夜看手机，回忆过去","prompt":"A cute white round-headed cartoon character sitting alone in a dark blue-black room at midnight, looking at phone with sad expression, dual-panel comic layout, deep dark blue and black color palette, oppressive emotional atmosphere, 3:4 ratio"},{"cardIndex":1,"description":"白色圆头小人在空荡的房间里，墙上日历全是加班标记","prompt":"A cute white round-headed cartoon character in empty dark room, calendar on wall marked with work dates, dual-panel comic layout, deep blue-black tones, emotional workplace illustration, 3:4 ratio"},{"cardIndex":2,"description":"白色圆头小人在办公桌前被堆成山的工作淹没","prompt":"A cute white round-headed cartoon character buried under paperwork at desk, dual-panel comic style, dark blue-black color scheme, emotional workplace illustration, 3:4 ratio"},{"cardIndex":3,"description":"白色圆头小人面对家人的催促，表情无奈","prompt":"A cute white round-headed cartoon character facing family pressure, dual-panel comic layout, dark blue-black tones, emotional family relationship illustration, 3:4 ratio"},{"cardIndex":4,"description":"白色圆头小人给对方找借口，内心在挣扎","prompt":"A cute white round-headed cartoon character with inner conflict, dual-panel comic, deep blue-black palette, relationship psychology illustration, 3:4 ratio"},{"cardIndex":5,"description":"白色圆头小人把委屈吞进肚子，最后决定爱自己","prompt":"A cute white round-headed cartoon character swallowing sadness, then transforming with self-love, dual-panel comic layout, dark blue to warm transition, emotional growth illustration, 3:4 ratio"}]
    """
}
