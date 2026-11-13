import Foundation
import CoreGraphics
import CoreText
import ImageIO
import PDFKit
import UniformTypeIdentifiers

// MARK: - 测试样本生成

func drawLines(_ lines: [(String, CGFloat)], in context: CGContext, size: CGSize, startX: CGFloat = 40) {
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(origin: .zero, size: size))
    var y = size.height - 60
    for (i, (text, fontSize)) in lines.enumerated() {
        let font = CTFontCreateWithName("PingFang SC" as CFString, fontSize, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: CGColor(gray: 0, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        context.textPosition = CGPoint(x: startX, y: y)
        CTLineDraw(line, context)
        // 行距取当前行与下一行字号的较大值，避免大字与上一行重叠
        let nextSize = i + 1 < lines.count ? lines[i + 1].1 : fontSize
        y -= max(fontSize, nextSize) * 1.6
    }
}

func makeTextPDF(lines: [(String, CGFloat)], to url: URL, size: CGSize = CGSize(width: 595, height: 842)) {
    var box = CGRect(origin: .zero, size: size)
    let consumer = CGDataConsumer(url: url as CFURL)!
    let ctx = CGContext(consumer: consumer, mediaBox: &box, nil)!
    ctx.beginPDFPage(nil)
    drawLines(lines, in: ctx, size: size)
    ctx.endPDFPage()
    ctx.closePDF()
}

func makeImage(lines: [(String, CGFloat)], to url: URL, size: CGSize = CGSize(width: 800, height: 1000)) {
    let ctx = CGContext(
        data: nil, width: Int(size.width), height: Int(size.height),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    drawLines(lines, in: ctx, size: size)
    let image = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
    CGImageDestinationFinalize(dest)
}

func makeImageOnlyPDF(imageURL: URL, to url: URL) {
    let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil)!
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    var box = CGRect(x: 0, y: 0, width: 595, height: 842)
    let consumer = CGDataConsumer(url: url as CFURL)!
    let ctx = CGContext(consumer: consumer, mediaBox: &box, nil)!
    ctx.beginPDFPage(nil)
    ctx.draw(image, in: CGRect(x: 20, y: 100, width: 555, height: 694))
    ctx.endPDFPage()
    ctx.closePDF()
}

// MARK: - 样本数据

let vatLines: [(String, CGFloat)] = [
    ("电子发票（普通发票）", 20),
    ("发票号码：24312000000012345678", 12),
    ("开票日期：2026年01月15日", 12),
    ("购买方名称：某某科技有限公司", 12),
    ("项目名称：*信息技术服务*软件开发服务", 12),
    ("金额 116.50  税率 6%  税额 6.95", 12),
    ("价税合计（大写）壹佰贰拾叁圆肆角伍分 （小写）¥123.45", 14),
    ("销售方名称：某某软件工作室", 12),
]

let trainLines: [(String, CGFloat)] = [
    ("中国铁路 电子客票报销凭证", 18),
    ("车次：G123  乘车日期：2026-01-10", 12),
    ("北京南站 → 上海虹桥站", 14),
    ("票价：￥553.00", 16),
    ("身份证号：110101199001011234", 10),
]

let wechatLines: [(String, CGFloat)] = [
    ("微信转账", 44),
    ("转账-转给张三", 30),
    ("-100.00", 90),
    ("转账时间 2026-01-08 12:30", 26),
    ("当前状态 已收钱", 26),
]

let bankLines: [(String, CGFloat)] = [
    ("招商银行 转账回单", 18),
    ("转账金额 ¥2,500.00", 16),
    ("收款人 李四", 12),
    ("转账日期 2026-01-05", 12),
]

// MARK: - 测试主流程

setvbuf(stdout, nil, _IONBF, 0)

let dir = FileManager.default.temporaryDirectory.appendingPathComponent("invoice-test-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
print("测试目录: \(dir.path)\n")

// 1. 生成样本
makeTextPDF(lines: vatLines, to: dir.appendingPathComponent("发票-软件服务.pdf"))
makeTextPDF(lines: trainLines, to: dir.appendingPathComponent("火车票-京沪.pdf"))
makeImage(lines: vatLines, to: dir.appendingPathComponent("IMG_0001.jpg"))
makeImage(lines: wechatLines, to: dir.appendingPathComponent("微信转账截图.png"), size: CGSize(width: 1170, height: 1500))
makeImage(lines: bankLines, to: dir.appendingPathComponent("银行回单.jpeg"))
// 无文本层 PDF（扫描件）
let scannedImage = dir.appendingPathComponent("_tmp_scanned.jpg")
makeImage(lines: vatLines, to: scannedImage)
makeImageOnlyPDF(imageURL: scannedImage, to: dir.appendingPathComponent("扫描件-餐饮.pdf"))
try FileManager.default.removeItem(at: scannedImage)

// 2. 解析器单元测试
print("=== AmountParser 单元测试 ===")
let parserCases: [(String, Double?, String)] = [
    ("价税合计（大写）壹佰贰拾叁圆肆角伍分 （小写）¥123.45", 123.45, "增值税发票"),
    ("票价：￥553.00", 553.00, "火车票"),
    ("转账金额 ¥2,500.00", 2500.00, "银行逗号金额"),
    ("-100.00", 100.00, "微信负数"),
    ("合计 ¥88.00", 88.00, "合计关键词"),
    ("吃饭花了 50.5元 打车", 50.5, "元兜底"),
    ("没有任何金额", nil, "无金额"),
]
var parserPassed = 0
for (text, expected, label) in parserCases {
    let result = AmountParser.parse(text)
    let ok = result.amount == expected
    print("\(ok ? "✅" : "❌") \(label): 期望 \(expected.map { String($0) } ?? "nil"), 实际 \(result.amount.map { String($0) } ?? "nil") [\(result.confidence.label)]")
    if ok { parserPassed += 1 }
}
print("解析器: \(parserPassed)/\(parserCases.count) 通过\n")

// 2a. 欧元/欧式数字测试
print("=== 欧元解析测试 ===")
let euroCases: [(String, Double?, String, String)] = [
    ("Gesamt betrag\nIm Rechnungsbetrag sind 7% Umsatzsteuer enthalten\n7,60 €", 7.60, "EUR", "德国发票 Gesamtbetrag"),
    ("24-StundenTicket 1 7,60 €", 7.60, "EUR", "数字+€ 兜底"),
    ("Total €12.50", 12.50, "EUR", "€ 前置"),
    ("Rechnungsbetrag 1.234,56 €", 1234.56, "EUR", "欧式千分位"),
    ("Amount due 99.99 EUR", 99.99, "EUR", "EUR 文字"),
    ("价税合计（小写）¥123.45", 123.45, "CNY", "人民币不受影响"),
]
var euroPassed = 0
for (text, expected, currency, label) in euroCases {
    let result = AmountParser.parse(text)
    let ok = result.amount == expected && result.currency == currency
    print("\(ok ? "✅" : "❌") \(label): 期望 \(expected.map { String($0) } ?? "nil") \(currency), 实际 \(result.amount.map { String($0) } ?? "nil") \(result.currency)")
    if ok { euroPassed += 1 }
}
print("欧元: \(euroPassed)/\(euroCases.count) 通过\n")

// 2b. 扩展字段解析测试
print("=== InvoiceFieldParser 单元测试 ===")
let vatText = """
电子发票(普通发票)
发票号码:24312000000012345678
开票日期:2026年01月15日
购买方名称:某某科技有限公司
销售方名称:某某软件工作室
价税合计（小写）¥123.45
"""
let verticalText = """
发票号码:26317000001935032411
开票日期:2026年06月08日
购
买
方
信
息
名称:福维克制造有限公司
销
售
方
信
息
名称:上海公共交通卡股份有限公司
"""
let bankText = "账单详情\n-¥153.00\n创建时间\n2026-08-12 09:51:17"
let trainText = "电子发票（铁路电子客票）\n发票号码:26349120093000680503\n开票日期:2026年11月11日\n票价:\n￥268.00\n购买方名称:福维克制作有限公司"

let fieldCases: [(String, String, String, String, String)] = [
    (vatText, "24312000000012345678", "2026-01-15", "某某软件工作室", "显式销售方"),
    (verticalText, "26317000001935032411", "2026-06-08", "上海公共交通卡股份有限公司", "竖排文本取第二个名称"),
    (bankText, "", "2026-08-12", "", "转账截图日期"),
    (trainText, "26349120093000680503", "2026-11-11", "", "火车票无销售方"),
    ("Rechnung\nNummer:\n0000001237\nDatum:\n25.9.2026\nWSW mobil GmbH", "0000001237", "2026-09-25", "", "德国发票 Nummer/Datum"),
]
var fieldPassed = 0
for (text, number, date, seller, label) in fieldCases {
    let f = InvoiceFieldParser.parse(text)
    let ok = f.invoiceNumber == number && f.issueDate == date && f.sellerName == seller
    print("\(ok ? "✅" : "❌") \(label): 号码=\(f.invoiceNumber) 日期=\(f.issueDate) 销售方=\(f.sellerName)")
    if ok { fieldPassed += 1 }
}
print("字段解析: \(fieldPassed)/\(fieldCases.count) 通过\n")

// 3. 扫描
let files = try FileScanner.scan(directory: dir)
print("=== 扫描到 \(files.count) 个文件 ===")
for f in files { print("  \(f.lastPathComponent)") }

// 4. 图片转 PDF + 识别
print("\n=== 转换 + 识别 ===")
var results: [(name: String, amount: Double?, confidence: RecognitionConfidence)] = []
for file in files {
    var pdfURL = file
    if FileScanner.isImage(file) {
        let dest = ImageToPDFConverter.destinationURL(for: file, in: dir)
        try ImageToPDFConverter.convert(imageAt: file, to: dest)
        pdfURL = dest
        // 验证 A4 且不放大
        if let doc = PDFDocument(url: dest), let page = doc.page(at: 0) {
            let bounds = page.bounds(for: .cropBox)
            assert(abs(bounds.width - 595.28) < 1 && abs(bounds.height - 841.89) < 1, "页面应为 A4")
        }
    }
    let output = await AmountRecognizer.recognize(fileAt: pdfURL)
    results.append((pdfURL.lastPathComponent, output.amount, output.confidence))
    print("  \(pdfURL.lastPathComponent): \(output.amount.map { String(format: "%.2f", $0) } ?? "未识别") [\(output.confidence.label)] \(output.snippet)")
}

// 5. 验证识别结果
print("\n=== 识别断言 ===")
let expectations: [String: Double] = [
    "发票-软件服务.pdf": 123.45,
    "火车票-京沪.pdf": 553.00,
    "IMG_0001.pdf": 123.45,
    "微信转账截图.pdf": 100.00,
    "银行回单.pdf": 2500.00,
    "扫描件-餐饮.pdf": 123.45,
]
var recognizePassed = 0
for (name, expected) in expectations {
    let actual = results.first { $0.name == name }?.amount
    let ok = actual == expected
    print("\(ok ? "✅" : "❌") \(name): 期望 \(expected), 实际 \(actual.map { String($0) } ?? "nil")")
    if ok { recognizePassed += 1 }
}
print("识别: \(recognizePassed)/\(expectations.count) 通过\n")

// 6. 重命名 + 撤销
print("=== 重命名测试 ===")
let sortedPDFs = FileScanner.naturalSort(files.map { f in
    FileScanner.isImage(f) ? dir.appendingPathComponent(f.deletingPathExtension().lastPathComponent + ".pdf") : f
})
var renameLog: [RenameRecord] = []
for (i, pdf) in sortedPDFs.enumerated() {
    guard let amount = results.first(where: { $0.name == pdf.lastPathComponent })?.amount else { continue }
    let newName = Renamer.newName(number: i + 1, amount: amount, originalName: pdf.lastPathComponent)
    let record = try Renamer.rename(from: pdf.lastPathComponent, to: newName, in: dir)
    renameLog.append(record)
    print("  \(pdf.lastPathComponent) → \(newName)")
}
let renamedFiles = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".pdf") }
let withAmount = results.filter { $0.amount != nil }.map(\.name)
assert(renamedFiles.filter { withAmount.contains($0) }.isEmpty, "有金额的文件应全部已重命名")
print("✅ 重命名完成，共 \(renameLog.count) 个")

try Renamer.undo(records: renameLog, in: dir)
let afterUndo = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".pdf") }
assert(afterUndo.contains("发票-软件服务.pdf"), "撤销后应恢复原名")
print("✅ 撤销恢复原名成功\n")

// 7. Excel 导出
print("=== Excel 导出测试 ===")
var items: [InvoiceItem] = []
for (i, r) in results.enumerated() {
    var item = InvoiceItem(originalName: r.name, currentName: r.name, kind: .pdf)
    item.amount = r.amount
    item.displayNo = i + 1
    if i < 3 { item.groupID = UUID() }
    items.append(item)
}
let groupA = InvoiceGroup(name: "A")
let groupB = InvoiceGroup(name: "B")
items[0].groupID = groupA.id
items[1].groupID = groupA.id
items[2].groupID = groupB.id
let rows = ExcelExporter.makeRows(items: items, groups: [groupA, groupB])
assert(rows[0].count == 9, "Excel 应为 9 列")
assert(rows.allSatisfy { $0.count == 9 }, "所有行应为 9 列")
let xlsxURL = dir.appendingPathComponent("发票清单.xlsx")
try XlsxWriter.write(rows: rows, to: xlsxURL)
print("✅ 已导出 \(xlsxURL.lastPathComponent) (\(try Data(contentsOf: xlsxURL).count) bytes, \(rows.count) 行)")

// 排除项测试：excluded 的发票不应出现在 Excel 中
var excludedItems = items
excludedItems[0].excluded = true
let excludedRows = ExcelExporter.makeRows(items: excludedItems, groups: [groupA, groupB])
let excludedName = excludedItems[0].currentName
let leaked = excludedRows.contains { row in
    if case .text(let name) = row[2].content { return name == excludedName }
    return false
}
assert(!leaked, "排除项不应导出到 Excel")
print("✅ 排除项不导出 Excel")

// 8. 合并 PDF
print("\n=== 合并测试 ===")
let pdfURLs = FileScanner.naturalSort(try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { $0.pathExtension == "pdf" })
let mergedURL = dir.appendingPathComponent("merged.pdf")
try PDFMerger.merge(urls: pdfURLs, to: mergedURL)
let merged = PDFDocument(url: mergedURL)!
print("✅ 合并 \(pdfURLs.count) 个 PDF → \(merged.pageCount) 页")

print("\n========== 测试完成 ==========")
print("解析器 \(parserPassed)/\(parserCases.count)，欧元 \(euroPassed)/\(euroCases.count)，字段 \(fieldPassed)/\(fieldCases.count)，识别 \(recognizePassed)/\(expectations.count)")
print("样本目录保留在: \(dir.path)")
