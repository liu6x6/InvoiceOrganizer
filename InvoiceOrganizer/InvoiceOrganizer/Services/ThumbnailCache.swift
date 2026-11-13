import Foundation
import PDFKit
import CoreGraphics
import ImageIO

actor ThumbnailCache {
    static let shared = ThumbnailCache()

    private var cache: [String: CGImage] = [:]

    func thumbnail(for url: URL, maxPixel: CGFloat = 96) -> CGImage? {
        let key = url.path
        if let cached = cache[key] { return cached }

        var image: CGImage?
        if FileScanner.isPDF(url) {
            if let document = PDFDocument(url: url), let page = document.page(at: 0) {
                let bounds = page.bounds(for: .cropBox)
                let longest = max(bounds.width, bounds.height)
                let dpi = longest > 0 ? 72 * maxPixel / longest : 72
                image = AmountRecognizer.render(page: page, dpi: dpi)
            }
        } else {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel * 2,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
                image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            }
        }

        if let image {
            if cache.count > 600 { cache.removeAll() }
            cache[key] = image
        }
        return image
    }

    func invalidate(url: URL) {
        cache.removeValue(forKey: url.path)
    }
}
