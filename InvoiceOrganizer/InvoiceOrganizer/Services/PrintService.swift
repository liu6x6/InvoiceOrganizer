import AppKit
import PDFKit

/// 打印：先把源 PDF 按设置（缩放/灰度）重排为纸张大小的打印文档，再走系统打印对话框。
@MainActor
enum PrintService {

    /// 页边距（ baked 进打印文档，系统打印对话框 margins 置 0 避免二次缩放）
    private static let margin: CGFloat = 18

    static func print(document: PDFDocument, settings: PrintSettings) {
        let baseInfo = NSPrintInfo.shared
        var paperSize = settings.paperSize.size ?? baseInfo.paperSize
        if settings.landscape {
            paperSize = CGSize(width: paperSize.height, height: paperSize.width)
        }
        guard let printDoc = buildPrintDocument(source: document, settings: settings, paperSize: paperSize) else { return }

        let info = baseInfo.copy() as! NSPrintInfo
        info.paperSize = paperSize
        info.topMargin = 0
        info.bottomMargin = 0
        info.leftMargin = 0
        info.rightMargin = 0
        info.scalingFactor = 1.0
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = true
        // 双面：kPMDuplexNone = 1, kPMDuplexNoTumble(长边) = 2
        info.dictionary()[NSPrintInfo.AttributeKey(rawValue: "duplex")] = NSNumber(value: settings.duplex ? 2 : 1)

        let view = PDFView(frame: NSRect(origin: .zero, size: paperSize))
        view.autoScales = true
        view.displayMode = .singlePage
        view.displayDirection = .vertical
        view.document = printDoc

        // 临时窗口承载 PDFView，保证打印渲染有正确的布局上下文
        let window = NSWindow(
            contentRect: view.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.layoutIfNeeded()

        // PDFKit 打印：文档已按纸张预缩放，scalingFactor 保持 1.0
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.showsPrintPanel = true
        operation.run()
        window.orderOut(nil)
    }

    /// 按缩放模式把每页绘制到纸张大小的新 PDF；灰度时以灰位图渲染
    static func buildPrintDocument(source: PDFDocument, settings: PrintSettings, paperSize: NSSize) -> PDFDocument? {
        let printable = CGSize(
            width: paperSize.width - margin * 2,
            height: paperSize.height - margin * 2
        )
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: paperSize)
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        for pageIndex in 0..<source.pageCount {
            guard let page = source.page(at: pageIndex) else { continue }
            let bounds = page.bounds(for: .cropBox)
            guard bounds.width > 0, bounds.height > 0 else { continue }

            let scale: CGFloat
            switch settings.scaleMode {
            case .fit:
                scale = min(printable.width / bounds.width, printable.height / bounds.height)
            case .percent:
                scale = CGFloat(settings.percent / 100.0)
            case .actual:
                scale = 1.0
            }

            let drawSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let origin = CGPoint(
                x: (paperSize.width - drawSize.width) / 2,
                y: (paperSize.height - drawSize.height) / 2
            )
            let destRect = CGRect(origin: origin, size: drawSize)

            context.beginPDFPage(nil)
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(mediaBox)

            if settings.grayscale {
                // 灰度：渲染为 300dpi 灰位图再绘制
                if let grayImage = renderGrayscale(page: page, bounds: bounds) {
                    context.draw(grayImage, in: destRect)
                }
            } else {
                context.saveGState()
                context.translateBy(x: origin.x, y: origin.y)
                context.scaleBy(x: scale, y: scale)
                context.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
                page.draw(with: .cropBox, to: context)
                context.restoreGState()
            }
            context.endPDFPage()
        }
        context.closePDF()
        return PDFDocument(data: data as Data)
    }

    private static func renderGrayscale(page: PDFPage, bounds: CGRect) -> CGImage? {
        let dpi: CGFloat = 300
        let scale = dpi / 72.0
        let width = Int(bounds.width * scale)
        let height = Int(bounds.height * scale)
        guard width > 0, height > 0,
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
              ) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
        page.draw(with: .cropBox, to: context)
        return context.makeImage()
    }
}
