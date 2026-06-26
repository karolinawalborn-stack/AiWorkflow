import Foundation

struct CopywritingParseResult {
    let cards: [CopywritingCard]
    let mode: ParseMode
    let rawText: String
    let error: String?
}

enum ParseMode: String {
    case json, text, textFallback, failed
}

enum CopywritingParser {

    /// 解析文案并确保结果数量 = expectedCount
    /// - 超出则截断
    /// - 不足则补空卡
    static func parse(rawText: String, expectedCount: Int = 6) -> CopywritingParseResult {
        print("📖 [CopyParser] 开始解析 长度=\(rawText.count) 期望\(expectedCount)张")

        // 1. JSON
        if let jsonResult = tryParseJSON(rawText) {
            let adjusted = normalizeCardCount(jsonResult, expected: expectedCount)
            let filled = adjusted.filter { !$0.topText.isEmpty }
            print("✅ [CopyParser] JSON 解析: raw=\(jsonResult.count) → adjusted=\(adjusted.count) 张 (含内容\(filled.count)张)")
            for c in adjusted { print("   card[\(c.cardIndex)] top=\(c.topText.prefix(30)) bottom=\(c.bottomText.prefix(30))") }
            return CopywritingParseResult(cards: adjusted, mode: .json, rawText: rawText, error: nil)
        }

        // 2. 按行文本解析
        if let textResult = parseTextLines(rawText) {
            let adjusted = normalizeCardCount(textResult, expected: expectedCount)
            let filled = adjusted.filter { !$0.topText.isEmpty && !$0.bottomText.isEmpty }
            print("✅ [CopyParser] 文本解析: raw=\(textResult.count) → adjusted=\(adjusted.count) 张 (完整\(filled.count)/\(adjusted.count))")
            for c in adjusted { print("   card[\(c.cardIndex)] top=\(c.topText.prefix(30)) bottom=\(c.bottomText.prefix(30)) purpose=\(c.purpose.prefix(20))") }
            return CopywritingParseResult(cards: adjusted, mode: .text, rawText: rawText, error: nil)
        }

        print("❌ [CopyParser] 全部解析失败")
        return CopywritingParseResult(cards: [], mode: .failed, rawText: rawText, error: "无法从返回内容中提取文案结构")
    }

    // MARK: - 数量归一化：截断或补齐到 expected 张

    private static func normalizeCardCount(_ cards: [CopywritingCard], expected: Int) -> [CopywritingCard] {
        if cards.count == expected {
            return cards
        } else if cards.count > expected {
            print("⚠️ [CopyParser] 卡片超出 \(expected) 张（实际 \(cards.count)），截断到 \(expected)")
            return Array(cards.prefix(expected))
        } else {
            print("⚠️ [CopyParser] 卡片不足 \(expected) 张（实际 \(cards.count)），补齐 \(expected - cards.count) 张空卡")
            var result = cards
            let existingIndices = Set(cards.map { $0.cardIndex })
            var nextIndex = 0
            for _ in 0..<(expected - cards.count) {
                while existingIndices.contains(nextIndex) { nextIndex += 1 }
                result.append(CopywritingCard(cardIndex: nextIndex))
                nextIndex += 1
            }
            return result
        }
    }

    // MARK: - JSON

    private static func tryParseJSON(_ text: String) -> [CopywritingCard]? {
        let data: Data
        if let d = text.data(using: .utf8) { data = d }
        else if let ex = extractBlock(text, "```json") { data = ex }
        else { return nil }

        let items: [[String: Any]]
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            items = arr
        } else if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let arr = dict["cards"] as? [[String: Any]] {
            items = arr
        } else { return nil }

        var cards: [CopywritingCard] = []
        for item in items {
            guard let idx = item["cardIndex"] as? Int else { continue }
            let top = (item["topText"] as? String) ?? (item["topFrame"] as? String) ?? (item["上半格文案"] as? String) ?? ""
            let bottom = (item["bottomText"] as? String) ?? (item["bottomFrame"] as? String) ?? (item["下半格文案"] as? String) ?? ""
            let purpose = (item["purpose"] as? String) ?? (item["这一张的作用"] as? String) ?? ""
            cards.append(CopywritingCard(cardIndex: idx, topText: top, bottomText: bottom, purpose: purpose))
        }
        return cards.isEmpty ? nil : cards
    }

    // MARK: - 行级文本解析

    private static func parseTextLines(_ text: String) -> [CopywritingCard]? {
        var cards: [CopywritingCard] = []
        let lines = text.components(separatedBy: .newlines)

        var ci = -1, top = "", bottom = "", purpose = ""

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            let isCardHeader = line.hasPrefix("第") && line.contains("张")
            let isCardHeader2 = line.hasPrefix("card") || line.hasPrefix("Card") || line.hasPrefix("CARD")

            if isCardHeader || isCardHeader2 {
                flushCard(&cards, ci, top, bottom, purpose)
                ci = extractNumber(line) ?? (ci + 1)
                top = ""; bottom = ""; purpose = ""
                continue
            }

            if let val = extractAfterColon(line, keywords: ["- 上半格文案", "上半格文案", "- 上半格", "上半格", "topText", "topFrame", "Top:"]) {
                top = val
                continue
            }
            if let val = extractAfterColon(line, keywords: ["- 下半格文案", "下半格文案", "- 下半格", "下半格", "bottomText", "bottomFrame", "Bottom:"]) {
                bottom = val
                continue
            }
            if let val = extractAfterColon(line, keywords: ["- 这一张的作用", "这一张的作用", "- 作用", "作用", "purpose", "Purpose:"]) {
                purpose = val
                continue
            }

            if line.contains("上半格") && !line.contains("下半格") {
                if top.isEmpty { top = extractFallback(line) }
                continue
            }
            if line.contains("下半格") {
                if bottom.isEmpty { bottom = extractFallback(line) }
                continue
            }
            if line.contains("作用") && purpose.isEmpty {
                purpose = extractFallback(line)
                continue
            }
        }

        flushCard(&cards, ci, top, bottom, purpose)

        if cards.isEmpty {
            for line in lines {
                let t = line.trimmingCharacters(in: .whitespaces)
                if let d = t.data(using: .utf8),
                   let item = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                   let idx = item["cardIndex"] as? Int {
                    let t2 = (item["topText"] as? String) ?? (item["topFrame"] as? String) ?? ""
                    let b2 = (item["bottomText"] as? String) ?? (item["bottomFrame"] as? String) ?? ""
                    cards.append(CopywritingCard(cardIndex: idx, topText: t2, bottomText: b2))
                }
            }
        }

        return cards.isEmpty ? nil : cards
    }

    // MARK: - 工具函数

    private static func flushCard(_ cards: inout [CopywritingCard], _ ci: Int, _ top: String, _ bottom: String, _ purpose: String) {
        guard ci >= 0 else { return }
        cards.append(CopywritingCard(cardIndex: ci, topText: top, bottomText: bottom, purpose: purpose))
    }

    private static func extractAfterColon(_ line: String, keywords: [String]) -> String? {
        var found = false
        var afterKeyword = line
        for kw in keywords {
            if let range = line.range(of: kw) {
                afterKeyword = String(line[range.upperBound...])
                found = true
                break
            }
        }
        guard found else { return nil }

        let colonChars: [Character] = ["：", ":"]
        for c in colonChars {
            if let idx = afterKeyword.firstIndex(of: c) {
                let val = String(afterKeyword[afterKeyword.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
                return val.isEmpty ? nil : val
            }
        }

        let val = afterKeyword.trimmingCharacters(in: .whitespaces)
        return val.isEmpty ? nil : val
    }

    private static func extractFallback(_ line: String) -> String {
        let colonChars: [Character] = ["：", ":"]
        for c in colonChars {
            if let idx = line.firstIndex(of: c) {
                let val = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
                if !val.isEmpty { return val }
            }
        }
        return line
    }

    private static func extractNumber(_ s: String) -> Int? {
        let digits = s.compactMap { $0.isNumber ? String($0) : nil }.joined()
        return Int(digits)
    }

    private static func extractBlock(_ text: String, _ marker: String) -> Data? {
        guard let r = text.range(of: marker),
              let e = text[r.upperBound...].range(of: "```") else { return nil }
        return String(text[r.upperBound..<e.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8)
    }
}
