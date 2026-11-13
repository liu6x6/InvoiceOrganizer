import Foundation
import PDFKit
import Vision
import CoreGraphics

nonisolated struct RecognitionOutput: Sendable {
    var amount: Double?
    var confidence: RecognitionConfidence
    var snippet: String
    var text: String
    var currency: String = "CNY"
    var fields: InvoiceFields = InvoiceFields()
}

/// 金额识别：PDF 文本层优先 → Vision OCR → 解析金额。纯本地、离线。
nonisolated enum AmountRecognizer {

    static func recognize(fileAt url: URL) async -> RecognitionOutput {
        var text = ""
        if FileScanner.isPDF(url) {
            if let document = PDFDocument(url: url) {
                let extracted = document.string ?? ""
                if extracted.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10 {
                    text = extracted
                } else if let page = document.page(at: 0),
                          let image = render(page: page, dpi: 220) {
                    text = await ocr(image: image)
                }
            }
        } else if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            text = await ocr(image: image)
        }

        let parsed = AmountParser.parse(text)
        return RecognitionOutput(
            amount: parsed.amount,
            confidence: parsed.confidence,
            snippet: parsed.snippet,
            text: text,
            currency: parsed.currency,
            fields: InvoiceFieldParser.parse(text)
        )
    }

    // MARK: - OCR

    static func ocr(image: CGImage) async -> String {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: "")
            }
        }
    }

    // MARK: - PDF 渲染

    static func render(page: PDFPage, dpi: CGFloat) -> CGImage? {
        let bounds = page.bounds(for: .cropBox)
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
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
        page.draw(with: .cropBox, to: context)
        return context.makeImage()
    }
}
