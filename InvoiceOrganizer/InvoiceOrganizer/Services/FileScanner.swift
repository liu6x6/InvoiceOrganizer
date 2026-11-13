import Foundation

nonisolated enum FileScanner {
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "tiff", "tif", "bmp", "webp"]
    static let pdfExtension = "pdf"

    /// 扫描目录中的发票相关文件（不递归），按文件名自然排序。
    /// 若同基础名的 PDF 已存在（图片已转换过），跳过图片避免重复。
    static func scan(directory: URL) throws -> [URL] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var pdfBases = Set<String>()
        var candidates: [URL] = []
        for url in contents {
            let ext = url.pathExtension.lowercased()
            if ext == pdfExtension {
                pdfBases.insert(url.deletingPathExtension().lastPathComponent)
                candidates.append(url)
            } else if imageExtensions.contains(ext) {
                candidates.append(url)
            }
        }
        let filtered = candidates.filter { url in
            if url.pathExtension.lowercased() == pdfExtension { return true }
            return !pdfBases.contains(url.deletingPathExtension().lastPathComponent)
        }
        return naturalSort(filtered)
    }

    static func naturalSort(_ urls: [URL]) -> [URL] {
        urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    static func isPDF(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == pdfExtension
    }

    static func isImage(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }
}
