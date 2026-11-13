import Foundation
import Compression

// MARK: - 单元格模型

nonisolated struct XCell: Sendable {
    enum Content: Sendable {
        case text(String)
        case number(Double)
        case formula(String)
    }
    var content: Content
    /// 0 默认 / 1 金额(0.00) / 2 加粗 / 3 加粗金额
    var style: Int = 0

    static func text(_ s: String, bold: Bool = false) -> XCell {
        XCell(content: .text(s), style: bold ? 2 : 0)
    }
    static func number(_ v: Double, bold: Bool = false) -> XCell {
        XCell(content: .number(v), style: bold ? 3 : 1)
    }
    static func formula(_ f: String, bold: Bool = false) -> XCell {
        XCell(content: .formula(f), style: bold ? 3 : 1)
    }
}

// MARK: - XLSX 生成（手写 OOXML，无第三方依赖）

nonisolated enum XlsxWriter {

    static func write(rows: [[XCell]], sheetName: String = "发票清单", to url: URL) throws {
        let parts: [(String, Data)] = [
            ("[Content_Types].xml", contentTypesXML.data(using: .utf8)!),
            ("_rels/.rels", relsXML.data(using: .utf8)!),
            ("xl/workbook.xml", workbookXML(sheetName: sheetName).data(using: .utf8)!),
            ("xl/_rels/workbook.xml.rels", workbookRelsXML.data(using: .utf8)!),
            ("xl/styles.xml", stylesXML.data(using: .utf8)!),
            ("xl/worksheets/sheet1.xml", sheetXML(rows: rows).data(using: .utf8)!),
        ]
        let archive = ZipWriter.archive(entries: parts)
        try archive.write(to: url, options: .atomic)
    }

    // MARK: Sheet XML

    private static func sheetXML(rows: [[XCell]]) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <cols><col min="1" max="1" width="6" customWidth="1"/><col min="2" max="2" width="10" customWidth="1"/><col min="3" max="3" width="48" customWidth="1"/><col min="4" max="4" width="14" customWidth="1"/><col min="5" max="5" width="8" customWidth="1"/><col min="6" max="6" width="12" customWidth="1"/><col min="7" max="7" width="32" customWidth="1"/><col min="8" max="8" width="24" customWidth="1"/><col min="9" max="9" width="26" customWidth="1"/></cols>
        <sheetData>
        """
        for (rowIndex, row) in rows.enumerated() {
            let rowNumber = rowIndex + 1
            xml += "<row r=\"\(rowNumber)\">"
            for (colIndex, cell) in row.enumerated() {
                let ref = "\(columnName(colIndex))\(rowNumber)"
                switch cell.content {
                case .text(let s):
                    xml += "<c r=\"\(ref)\" s=\"\(cell.style)\" t=\"inlineStr\"><is><t>\(escapeXML(s))</t></is></c>"
                case .number(let v):
                    xml += "<c r=\"\(ref)\" s=\"\(cell.style)\"><v>\(v)</v></c>"
                case .formula(let f):
                    xml += "<c r=\"\(ref)\" s=\"\(cell.style)\"><f>\(escapeXML(f))</f><v>0</v></c>"
                }
            }
            xml += "</row>"
        }
        xml += "</sheetData></worksheet>"
        return xml
    }

    private static func columnName(_ index: Int) -> String {
        var n = index
        var name = ""
        repeat {
            name = String(UnicodeScalar(UInt8(65 + n % 26))) + name
            n = n / 26 - 1
        } while n >= 0
        return name
    }

    private static func escapeXML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    // MARK: 固定部件

    private static let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>
    """

    private static let relsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
    """

    private static func workbookXML(sheetName: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="\(escapeXML(sheetName))" sheetId="1" r:id="rId1"/></sheets></workbook>
        """
    }

    private static let workbookRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>
    """

    private static let stylesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="1"><numFmt numFmtId="164" formatCode="0.00"/></numFmts><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="4"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="164" fontId="1" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/></cellXfs></styleSheet>
    """
}

// MARK: - 最小 ZIP 打包器（deflate 用系统 Compression 框架）

nonisolated enum ZipWriter {

    static func archive(entries: [(name: String, data: Data)]) -> Data {
        var output = Data()
        var central = Data()
        let (dosTime, dosDate) = dosTimestamp()

        for entry in entries {
            let nameData = Data(entry.name.utf8)
            let raw = entry.data
            let crc = crc32(raw)
            let compressed = deflate(raw)
            let useDeflate = compressed.count < raw.count
            let payload = useDeflate ? compressed : raw
            let method: UInt16 = useDeflate ? 8 : 0
            let offset = UInt32(output.count)

            // Local file header
            output.appendLE(UInt32(0x0403_4b50))
            output.appendLE(UInt16(20))          // version needed
            output.appendLE(UInt16(0x0800))      // UTF-8 flag
            output.appendLE(method)
            output.appendLE(dosTime)
            output.appendLE(dosDate)
            output.appendLE(crc)
            output.appendLE(UInt32(payload.count))
            output.appendLE(UInt32(raw.count))
            output.appendLE(UInt16(nameData.count))
            output.appendLE(UInt16(0))           // extra len
            output.append(nameData)
            output.append(payload)

            // Central directory header
            central.appendLE(UInt32(0x0201_4b50))
            central.appendLE(UInt16(20))         // version made by
            central.appendLE(UInt16(20))         // version needed
            central.appendLE(UInt16(0x0800))
            central.appendLE(method)
            central.appendLE(dosTime)
            central.appendLE(dosDate)
            central.appendLE(crc)
            central.appendLE(UInt32(payload.count))
            central.appendLE(UInt32(raw.count))
            central.appendLE(UInt16(nameData.count))
            central.appendLE(UInt16(0))          // extra
            central.appendLE(UInt16(0))          // comment
            central.appendLE(UInt16(0))          // disk
            central.appendLE(UInt16(0))          // internal attrs
            central.appendLE(UInt32(0))          // external attrs
            central.appendLE(offset)
            central.append(nameData)
        }

        let centralOffset = UInt32(output.count)
        output.append(central)

        // End of central directory
        output.appendLE(UInt32(0x0605_4b50))
        output.appendLE(UInt16(0))
        output.appendLE(UInt16(0))
        output.appendLE(UInt16(entries.count))
        output.appendLE(UInt16(entries.count))
        output.appendLE(UInt32(central.count))
        output.appendLE(centralOffset)
        output.appendLE(UInt16(0))
        return output
    }

    private static func deflate(_ data: Data) -> Data {
        guard !data.isEmpty else { return Data() }
        let capacity = data.count + 4096
        var destination = Data(count: capacity)
        let written = destination.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_encode_buffer(
                    dst.bindMemory(to: UInt8.self).baseAddress!, capacity,
                    src.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else { return data }
        return destination.prefix(written)
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ crcTable[index]
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static let crcTable: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    private static func dosTimestamp() -> (time: UInt16, date: UInt16) {
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date())
        let year = max(1980, comps.year ?? 1980)
        let date = UInt16(((year - 1980) << 9) | ((comps.month ?? 1) << 5) | (comps.day ?? 1))
        let time = UInt16(((comps.hour ?? 0) << 11) | ((comps.minute ?? 0) << 5) | ((comps.second ?? 0) / 2))
        return (time, date)
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
}
