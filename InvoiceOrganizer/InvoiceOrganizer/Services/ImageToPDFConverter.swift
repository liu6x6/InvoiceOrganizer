import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// 图片 → 单页 A4 PDF：保持比例、居中，只缩小不放大。
nonisolated enum ImageToPDFConverter {
    static let a4Size = CGSize(width: 595.28, height: 841.89)

    enum ConvertError: Error, LocalizedError {
        case cannotReadImage
        case cannotCreateContext

        var errorDescription: String? {
            switch self {
            case .cannotReadImage: return "无法读取图片"
            case .cannotCreateContext: return "无法创建 PDF 上下文"
            }
        }
    }

    @discardableResult
    static func convert(imageAt source: URL, to destination: URL) throws -> URL {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw ConvertError.cannotReadImage
        }

        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)
        // 只缩小不放大
        let scale = min(1.0, a4Size.width / imgW, a4Size.height / imgH)
        let drawSize = CGSize(width: imgW * scale, height: imgH * scale)
        let origin = CGPoint(
            x: (a4Size.width - drawSize.width) / 2,
            y: (a4Size.height - drawSize.height) / 2
        )

        var mediaBox = CGRect(origin: .zero, size: a4Size)
        guard let consumer = CGDataConsumer(url: destination as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ConvertError.cannotCreateContext
        }

        context.beginPDFPage(nil)
        // 白底
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(mediaBox)
        context.draw(cgImage, in: CGRect(origin: origin, size: drawSize))
        context.endPDFPage()
        context.closePDF()
        return destination
    }

    /// 生成不冲突的目标 PDF 路径（同基础名，若占用则加 -1/-2…）
    static func destinationURL(for imageURL: URL, in directory: URL) -> URL {
        let base = imageURL.deletingPathExtension().lastPathComponent
        var candidate = directory.appendingPathComponent(base).appendingPathExtension("pdf")
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(counter)").appendingPathExtension("pdf")
            counter += 1
        }
        return candidate
    }
}
