import Foundation

nonisolated struct InvoiceFields: Sendable {
    var invoiceNumber: String = ""
    var issueDate: String = ""
    var sellerName: String = ""
}

/// 从发票文本中提取扩展字段：发票号码、开票日期、销售方名称。
/// 转账截图提取转账时间作为日期。尽力而为，识别不到留空。
nonisolated enum InvoiceFieldParser {

    static func parse(_ rawText: String) -> InvoiceFields {
        let text = AmountParser.normalize(rawText)
        var fields = InvoiceFields()

        // 发票号码：8-20 位数字（数电票 20 位，老发票 8 位；德国 Rechnung 的 Nummer）
        if let groups = matchGroups(#"发票号码\s*[:：]?\s*([0-9]{8,20})"#, in: text) {
            fields.invoiceNumber = groups[0]
        } else if let groups = matchGroups(#"(?<![A-Za-z])Nummer\s*[:：]?\s*([0-9]{4,20})"#, in: text) {
            fields.invoiceNumber = groups[0]
        } else if text.contains("Nummer") || text.contains("Rechnung"),
                  let groups = matchGroups(#"(?m)^[ \t]*([0-9]{8,20})[ \t]*$"#, in: text) {
            // 兜底：两栏 OCR 布局标签与值分离时，取独立成行的长数字
            fields.invoiceNumber = groups[0]
        }

        // 开票日期：2026年01月15日 → 2026-01-15
        if let groups = matchGroups(#"开票日期\s*[:：]?\s*([0-9]{4})\s*年\s*([0-9]{1,2})\s*月\s*([0-9]{1,2})\s*日"#, in: text),
           let y = Int(groups[0]), let m = Int(groups[1]), let d = Int(groups[2]) {
            fields.issueDate = String(format: "%04d-%02d-%02d", y, m, d)
        } else if let groups = matchGroups(#"(?:转账时间|创建时间|交易时间|转账日期)\s*[:：]?\s*([0-9]{4})[-年/]([0-9]{1,2})[-月/]([0-9]{1,2})"#, in: text),
                  let y = Int(groups[0]), let m = Int(groups[1]), let d = Int(groups[2]) {
            fields.issueDate = String(format: "%04d-%02d-%02d", y, m, d)
        } else if let groups = matchGroups(#"(?:^|[\s\n])([0-9]{4})-([0-9]{1,2})-([0-9]{1,2})(?![0-9])"#, in: text),
                  let y = Int(groups[0]), let m = Int(groups[1]), let d = Int(groups[2]),
                  (1...12).contains(m), (1...31).contains(d) {
            // 兜底：截图 OCR 两栏布局导致标签与日期分离时，取独立 ISO 日期
            fields.issueDate = String(format: "%04d-%02d-%02d", y, m, d)
        } else if let groups = matchGroups(#"Datum\s*[:：]?\s*([0-9]{1,2})\.([0-9]{1,2})\.([0-9]{4})"#, in: text),
                  let d = Int(groups[0]), let m = Int(groups[1]), let y = Int(groups[2]) {
            // 德国发票日期：25.9.2026 → 2026-09-25
            fields.issueDate = String(format: "%04d-%02d-%02d", y, m, d)
        } else if let groups = matchGroups(#"(?<![0-9.])([0-9]{1,2})\.([0-9]{1,2})\.([0-9]{4})(?![0-9.])"#, in: text),
                  let d = Int(groups[0]), let m = Int(groups[1]), let y = Int(groups[2]),
                  (1...12).contains(m), (1...31).contains(d) {
            // 兜底：两栏布局下独立的德式日期
            fields.issueDate = String(format: "%04d-%02d-%02d", y, m, d)
        }

        // 销售方名称：
        // 1. 显式 "销售方名称:xxx"
        // 2. 标准发票布局中 "名称:" 出现两次（购买方、销售方），取第二个
        //    （竖排"销售方信息"被提取为单字时也能命中）
        if let groups = matchGroups(#"销售方名称\s*[:：]\s*([^\n]{2,40})"#, in: text) {
            fields.sellerName = groups[0].trimmingCharacters(in: .whitespaces)
        } else {
            let allNames = allMatchGroups(#"名称\s*[:：]\s*([^\n]{2,40})"#, in: text)
            if allNames.count >= 2 {
                fields.sellerName = allNames[1][0].trimmingCharacters(in: .whitespaces)
            }
        }

        return fields
    }

    // MARK: - Helpers

    /// 返回第一个匹配的所有捕获组
    private static func matchGroups(_ pattern: String, in text: String) -> [String]? {
        allMatchGroups(pattern, in: text).first
    }

    private static func allMatchGroups(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.compactMap { match in
            guard match.numberOfRanges >= 2 else { return nil }
            var groups: [String] = []
            for i in 1..<match.numberOfRanges {
                guard let range = Range(match.range(at: i), in: text) else { return nil }
                groups.append(String(text[range]))
            }
            return groups
        }
    }
}
