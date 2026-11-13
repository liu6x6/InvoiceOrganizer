import Foundation

nonisolated struct AmountParseResult: Sendable {
    var amount: Double?
    var confidence: RecognitionConfidence
    var snippet: String
    var currency: String = "CNY"
}

/// 从发票/截图文本中提取金额。
/// 中文票据优先级：价税合计 > 票价 > 转账/付款金额 > 实付/合计 > 负数金额(微信) > ¥符号金额 > 数字+元
/// 欧洲票据：Gesamtbetrag/Total 等关键词 > 数字+€ > €+数字 > 数字+EUR
nonisolated enum AmountParser {

    /// 欧式数字：1.234,56 / 7,60 / 7.60
    private static let eurNumber = #"([0-9]{1,3}(?:\.[0-9]{3})+,[0-9]{1,2}|[0-9]+,[0-9]{1,2}|[0-9]+\.[0-9]{2})"#

    static func parse(_ rawText: String) -> AmountParseResult {
        let text = normalize(rawText)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AmountParseResult(amount: nil, confidence: .none, snippet: "")
        }

        let number = #"([0-9][0-9,]*(?:\.[0-9]{1,2})?)"#

        // (pattern, confidence, 是否取最大值, 币种, 是否欧式数字)
        let rules: [(String, RecognitionConfidence, Bool, String, Bool)] = [
            // 增值税发票：价税合计（小写）¥123.45
            (#"价税合计[\s\S]{0,60}?[¥￥]\s*"# + number, .high, false, "CNY", false),
            (#"价税合计[\s\S]{0,60}?小写[\s\S]{0,20}?"# + number, .high, false, "CNY", false),
            // 火车票：票价 ¥54.50
            (#"票\s*价[\s\S]{0,20}?[¥￥]?\s*"# + number, .high, false, "CNY", false),
            // 转账截图（微信/银行）
            (#"(?:转账金额|付款金额|交易金额|支付金额|汇款金额|转出金额)[\s\S]{0,30}?[¥￥]?\s*[-−]?\s*"# + number, .high, false, "CNY", false),
            // 微信转账详情中的负数金额 -100.00
            (#"[-−]\s*[¥￥]?\s*([0-9][0-9,]*\.[0-9]{2})"#, .medium, false, "CNY", false),
            // 其他常见关键词 + ¥
            (#"(?:实付|应付|合计|金额)[\s\S]{0,20}?[¥￥]\s*"# + number, .medium, false, "CNY", false),
            // 欧洲发票：总额关键词 + 数字 + €（Gesamtbetrag 可能被 OCR 拆成 Gesamt betrag）
            (#"(?:Gesamtbetrag|Gesamt\s*betrag|Rechnungsbetrag|Endbetrag|Summe|Total|Zu\s*zahlen|Amount\s*due)[\s\S]{0,60}?"# + eurNumber + #"\s*€"#, .high, false, "EUR", true),
            // 数字 + €（取最大，发票总额通常最大）
            (eurNumber + #"\s*€"#, .medium, true, "EUR", true),
            // € + 数字（前置符号风格）
            (#"€\s*"# + eurNumber, .medium, true, "EUR", true),
            // 数字 + EUR/Euro
            (eurNumber + #"\s*(?:EUR|Euro)\b"#, .low, true, "EUR", true),
            // 兜底：所有 ¥ 金额取最大（发票价税合计通常是最大金额）
            (#"[¥￥]\s*"# + number, .low, true, "CNY", false),
            // 兜底：xx.xx 元
            (#"([0-9][0-9,]*(?:\.[0-9]{1,2})?)\s*元"#, .low, true, "CNY", false),
            // 兜底：独立的小数金额（截图中的大号金额，低置信度）
            (#"(?:^|[\s,，:：])([0-9][0-9,]*\.[0-9]{2})(?![0-9%])"#, .low, true, "CNY", false),
        ]

        for (pattern, confidence, pickMax, currency, european) in rules {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            var candidates: [(Double, String)] = []
            for match in matches {
                guard match.numberOfRanges >= 2,
                      let amountRange = Range(match.range(at: 1), in: text),
                      let value = european
                        ? parseEuropeanNumber(String(text[amountRange]))
                        : parseNumber(String(text[amountRange])) else { continue }
                let snippet = snippetAround(match.range, in: text)
                candidates.append((value, snippet))
            }
            guard !candidates.isEmpty else { continue }
            let chosen = pickMax ? candidates.max(by: { $0.0 < $1.0 })! : candidates[0]
            return AmountParseResult(amount: chosen.0, confidence: confidence, snippet: chosen.1, currency: currency)
        }

        return AmountParseResult(amount: nil, confidence: .none, snippet: "")
    }

    // MARK: - Helpers

    /// 全角 → 半角，统一货币符号
    static func normalize(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            var s = scalar
            // 全角数字/符号 (FF01-FF5E) → 半角
            if s.value >= 0xFF01 && s.value <= 0xFF5E {
                s = Unicode.Scalar(s.value - 0xFEE0)!
            }
            if s == "￥" { s = "¥" }
            // 各种破折号/减号 → 半角连字符
            if s == "–" || s == "—" || s == "−" { s = "-" }
            result.unicodeScalars.append(s)
        }
        return result
    }

    /// 中式/美式数字：逗号千分位，点小数
    static func parseNumber(_ raw: String) -> Double? {
        let cleaned = raw.replacingOccurrences(of: ",", with: "")
        guard let value = Double(cleaned), value > 0, value < 100_000_000 else { return nil }
        return value
    }

    /// 欧式数字：点千分位，逗号小数（7,60 / 1.234,56）；纯点时按位数判断
    static func parseEuropeanNumber(_ raw: String) -> Double? {
        var s = raw
        if s.contains(",") {
            s = s.replacingOccurrences(of: ".", with: "")
            s = s.replacingOccurrences(of: ",", with: ".")
        } else if s.contains(".") {
            let parts = s.split(separator: ".")
            if !(parts.count == 2 && parts[1].count == 2) {
                // 1.234 / 1.234.567 → 点为千分位
                s = s.replacingOccurrences(of: ".", with: "")
            }
            // 7.60 → 点为小数
        }
        guard let value = Double(s), value > 0, value < 100_000_000 else { return nil }
        return value
    }

    private static func snippetAround(_ range: NSRange, in text: String) -> String {
        guard let r = Range(range, in: text) else { return "" }
        // 取匹配所在的整行
        let lineStart = text[..<r.lowerBound].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        let lineEnd = text[r.upperBound...].firstIndex(of: "\n") ?? text.endIndex
        let line = text[lineStart..<lineEnd].trimmingCharacters(in: .whitespaces)
        return String(line.prefix(80))
    }
}
