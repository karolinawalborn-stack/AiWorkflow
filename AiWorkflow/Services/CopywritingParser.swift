import Foundation

// ═══════════════════════════════════════════════════════
//  文案解析器——将模型原始返回转为结构化的 CopywritingCard
// ═══════════════════════════════════════════════════════
//
//  支持两种输入格式：
//  1. JSON 数组：[{"cardIndex":0,"topText":"...","bottomText":"...","purpose":"..."}]
//  2. 文本格式：
//     第1张
//     - 上半格文案：
//     - 下半格文案：
//     - 这一张的作用：
//
//  如果 JSON 解析失败，自动 fallback 到文本解析。
//  如果都失败，返回错误原因 + 原始文本。
// ═══════════════════════════════════════════════════════

struct CopywritingParseResult {
    let cards: [CopywritingCard]
    let mode: ParseMode
    let rawText: String
    let error: String?
}

enum ParseMode: String {
    case json, text, failed
}

enum CopywritingParser {

    /// 解析原始返回文本，优先 JSON 再 fallback 文本
    static func parse(rawText: String, expectedCount: Int = 6) -> CopywritingParseResult {
        print("📖 [CopyParser] 开始解析，长度=\(rawText.count)字符，期望\(expectedCount)张")

        // 1. 尝试 JSON
        if let jsonResult = tryParseJSON(rawText, expectedCount: expectedCount) {
            print("✅ [CopyParser] JSON 解析成功: \(jsonResult.count) 张")
            return CopywritingParseResult(cards: jsonResult, mode: .json, rawText: rawText, error: nil)
        }

        // 2. 尝试文本解析
        if let textResult = tryParseText(rawText, expectedCount: expectedCount) {
            print("✅ [CopyParser] 文本解析成功: \(textResult.count) 张")
            return CopywritingParseResult(cards: textResult, mode: .text, rawText: rawText, error: nil)
        }

        // 3. 都失败
        print("❌ [CopyParser] 所有解析方式都失败")
        return CopywritingParseResult(cards: [], mode: .failed, rawText: rawText, error: "无法从返回内容中提取文案结构")
    }

    // MARK: - JSON 解析

    /// 尝试 JSON 解析，支持 "topText"/"bottomText" 和 "topFrame"/"bottomFrame" 两种字段名
    private static func tryParseJSON(_ text: String, expectedCount: Int) -> [CopywritingCard]? {
        let data: Data
        if let d = text.data(using: .utf8) { data = d }
        else if let ex = extractJSONBlock(text) { data = ex }
        else { return nil }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            // 也可能是单层对象 {"cards": [...]}
            if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let cards = dict["cards"] as? [[String: Any]] {
                return parseJSONArray(cards)
            }
            return nil
        }
        return parseJSONArray(json)
    }

    private static func parseJSONArray(_ items: [[String: Any]]) -> [CopywritingCard]? {
        var cards: [CopywritingCard] = []
        for item in items {
            guard let idx = item["cardIndex"] as? Int else { continue }
            // 兼容两种字段名
            let top = (item["topText"] as? String) ?? (item["topFrame"] as? String) ?? ""
            let bottom = (item["bottomText"] as? String) ?? (item["bottomFrame"] as? String) ?? ""
            let purpose = (item["purpose"] as? String) ?? (item["这一张的作用"] as? String) ?? ""
            cards.append(CopywritingCard(cardIndex: idx, topText: top, bottomText: bottom, purpose: purpose))
        }
        return cards.isEmpty ? nil : cards
    }

    // MARK: - 文本解析

    /// 尝试文本格式解析：
    ///   第X张
    ///   - 上半格文案：
    ///   - 下半格文案：
    ///   - 这一张的作用：
    private static func tryParseText(_ text: String, expectedCount: Int) -> [CopywritingCard]? {
        var cards: [CopywritingCard] = []
        let lines = text.components(separatedBy: .newlines)

        var currentIdx = -1
        var currentTop = ""
        var currentBottom = ""
        var currentPurpose = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 匹配 "第X张" 或 "第X张图"
            if trimmed.hasPrefix("第"), trimmed.contains("张") {
                // 保存上一张
                if currentIdx >= 0 {
                    cards.append(CopywritingCard(cardIndex: currentIdx, topText: currentTop, bottomText: currentBottom, purpose: currentPurpose))
                }
                // 提取数字
                let numStr = trimmed
                    .replacingOccurrences(of: "第", with: "")
                    .replacingOccurrences(of: "张", with: "")
                    .replacingOccurrences(of: "图", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: " :-—"))
                currentIdx = Int(numStr) ?? (currentIdx + 1)
                currentTop = ""; currentBottom = ""; currentPurpose = ""
                continue
            }

            if trimmed.hasPrefix("- 上半格文案") || trimmed.hasPrefix("上半格文案") || trimmed.hasPrefix("- 上半格") {
                currentTop = extractValue(trimmed)
            } else if trimmed.hasPrefix("- 下半格文案") || trimmed.hasPrefix("下半格文案") || trimmed.hasPrefix("- 下半格") {
                currentBottom = extractValue(trimmed)
            } else if trimmed.hasPrefix("- 这一张的作用") || trimmed.hasPrefix("这一张的作用") || trimmed.hasPrefix("这一张的作用") {
                currentPurpose = extractValue(trimmed)
            } else if trimmed.contains("上半格"), !trimmed.contains("下半格") {
                if currentTop.isEmpty { currentTop = trimmed }
            } else if trimmed.contains("下半格") {
                if currentBottom.isEmpty { currentBottom = trimmed }
            }
        }

        // 保存最后一张
        if currentIdx >= 0 {
            cards.append(CopywritingCard(cardIndex: currentIdx, topText: currentTop, bottomText: currentBottom, purpose: currentPurpose))
        }

        // 也尝试解析简单的 JSON-formatted 行
        if cards.isEmpty {
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if let data = trimmed.data(using: .utf8),
                   let item = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let idx = item["cardIndex"] as? Int {
                    let top = (item["topText"] as? String) ?? (item["topFrame"] as? String) ?? ""
                    let bottom = (item["bottomText"] as? String) ?? (item["bottomFrame"] as? String) ?? ""
                    cards.append(CopywritingCard(cardIndex: idx, topText: top, bottomText: bottom))
                }
            }
        }

        return cards.isEmpty ? nil : cards
    }

    // MARK: - 工具

    private static func extractValue(_ line: String) -> String {
        // 找冒号或：后面的内容
        if let range = line.range(of: "：") {
            return String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        if let range = line.range(of: ":") {
            return String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return ""
    }

    private static func extractJSONBlock(_ text: String) -> Data? {
        guard let r = text.range(of: "```json"),
              let e = text[r.upperBound...].range(of: "```") else { return nil }
        return String(text[r.upperBound..<e.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .data(using: .utf8)
    }
}
