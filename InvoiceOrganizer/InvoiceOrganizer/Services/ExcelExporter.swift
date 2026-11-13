import Foundation

/// 把发票清单组装成 Excel 行：表头 + 分组明细/小计 + 总计（SUM 公式）
nonisolated enum ExcelExporter {

    static func makeRows(items: [InvoiceItem], groups: [InvoiceGroup]) -> [[XCell]] {
        var rows: [[XCell]] = []
        rows.append([
            XCell.text("序号", bold: true),
            XCell.text("组别", bold: true),
            XCell.text("文件名", bold: true),
            XCell.text("金额", bold: true),
            XCell.text("币种", bold: true),
            XCell.text("开票日期", bold: true),
            XCell.text("销售方", bold: true),
            XCell.text("发票号码", bold: true),
            XCell.text("备注", bold: true),
        ])

        let sorted = items.filter { !$0.excluded }.sorted { $0.displayNo < $1.displayNo }
        let grouped = Dictionary(grouping: sorted, by: { $0.groupID })
        var sections: [(label: String, items: [InvoiceItem])] = []
        for group in groups {
            if let groupItems = grouped[group.id], !groupItems.isEmpty {
                sections.append((group.name, groupItems))
            }
        }
        if let ungrouped = grouped[nil], !ungrouped.isEmpty {
            sections.append(("未分组", ungrouped))
        }

        var currentRow = 2 // 表头占第 1 行
        var allAmountRefs: [String] = []

        for section in sections {
            var sectionRefs: [String] = []
            for item in section.items {
                var amountCell = XCell.text("")
                if let amount = item.amount {
                    amountCell = XCell.number(amount)
                    let ref = "D\(currentRow)"
                    sectionRefs.append(ref)
                    allAmountRefs.append(ref)
                }
                rows.append([
                    XCell.number(Double(item.displayNo)),
                    XCell.text(section.label),
                    XCell.text(item.currentName),
                    amountCell,
                    XCell.text(item.currency),
                    XCell.text(item.issueDate),
                    XCell.text(item.sellerName),
                    XCell.text(item.invoiceNumber),
                    XCell.text(item.note),
                ])
                currentRow += 1
            }
            // 分组小计（多于一个分组时才显示，避免冗余）
            if sections.count > 1 && !sectionRefs.isEmpty {
                rows.append([
                    XCell.text(""),
                    XCell.text(""),
                    XCell.text("\(section.label) 小计", bold: true),
                    XCell.formula(sumFormula(sectionRefs), bold: true),
                    XCell.text(""),
                    XCell.text(""),
                    XCell.text(""),
                    XCell.text(""),
                    XCell.text(""),
                ])
                currentRow += 1
            }
        }

        // 总计
        rows.append([
            XCell.text(""),
            XCell.text(""),
            XCell.text("总计", bold: true),
            XCell.formula(sumFormula(allAmountRefs), bold: true),
            XCell.text(""),
            XCell.text(""),
            XCell.text(""),
            XCell.text(""),
            XCell.text(""),
        ])
        return rows
    }

    /// 连续行合并为区间，如 SUM(D2:D5,D8,D10:D12)
    private static func sumFormula(_ refs: [String]) -> String {
        guard !refs.isEmpty else { return "0" }
        let numbers = refs.compactMap { Int($0.dropFirst()) }.sorted()
        var ranges: [String] = []
        var start = numbers[0]
        var prev = numbers[0]
        for n in numbers.dropFirst() {
            if n == prev + 1 {
                prev = n
            } else {
                ranges.append(start == prev ? "D\(start)" : "D\(start):D\(prev)")
                start = n
                prev = n
            }
        }
        ranges.append(start == prev ? "D\(start)" : "D\(start):D\(prev)")
        return "SUM(\(ranges.joined(separator: ",")))"
    }
}
