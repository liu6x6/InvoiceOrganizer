import Foundation
import PDFKit

nonisolated enum PDFMerger {
    /// 按顺序合并 PDF 并写入目标文件
    static func merge(urls: [URL], to destination: URL) throws {
        let merged = PDFDocument()
        var index = 0
        for url in urls {
            guard let document = PDFDocument(url: url) else { continue }
            for pageIndex in 0..<document.pageCount {
                guard let page = document.page(at: pageIndex) else { continue }
                merged.insert(page, at: index)
                index += 1
            }
        }
        guard merged.pageCount > 0 else {
            throw NSError(domain: "PDFMerger", code: 1, userInfo: [NSLocalizedDescriptionKey: "没有可合并的 PDF 页面"])
        }
        guard merged.write(to: destination) else {
            throw NSError(domain: "PDFMerger", code: 2, userInfo: [NSLocalizedDescriptionKey: "写入合并 PDF 失败"])
        }
    }
}
