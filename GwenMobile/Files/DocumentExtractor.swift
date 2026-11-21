import GwenMobileKit
import Foundation
import PDFKit
import UIKit
import CoreGraphics

struct ExtractedText {
    let text: String
    let pages: Int?
    let chars: Int
    let truncated: Bool
    let via: ExtractionVia
}

enum DocumentExtractor {
    private static let nothing = ExtractedText(text: "", pages: nil, chars: 0, truncated: false, via: .none)

    static func extract(url: URL, kind: FileKind, ocrLanguages: [String]) -> ExtractedText {
        switch kind {
        case .pdf:
            return extractPDF(url: url, languages: ocrLanguages)
        case .rtf:
            return extractRichText(url: url, languages: ocrLanguages)
        case .docx:
            return extractWordDocument(url: url)
        case .video:
            return nothing
        case .text, .csv, .json:
            guard let data = try? Data(contentsOf: url) else {
                return nothing
            }
            return excerpted(PlainTextDecoding.text(of: data), via: .plain)
        }
    }

    private static func extractWordDocument(url: URL) -> ExtractedText {
        guard let data = try? Data(contentsOf: url),
              let text = DocxText.text(from: data) else {
            return nothing
        }
        return excerpted(text, via: .docx)
    }

    private static func extractRichText(url: URL, languages: [String]) -> ExtractedText {
        let document = RichTextFile.read(url: url)
        guard document.hasPictures else { return excerpted(document.text, via: .richText) }
        var scanned: [String] = []
        for picture in document.pictures.prefix(FilePolicy.maxOCRPages) {
            guard let text = TextRecognizing.recognize(data: picture, languages: languages) else { continue }
            scanned.append(text)
        }
        guard !scanned.isEmpty else { return excerpted(document.text, via: .richText) }
        let parts = [excerpted(document.text, via: .richText).text, FileTextBlocks.pageMarked(scanned)]
            .filter { !$0.isEmpty }
        let excerpt = FileTextBlocks.excerpt(parts.joined(separator: "\n\n"),
                                             limit: FilePolicy.maxTextChars)
        return ExtractedText(text: excerpt.text, pages: document.pictures.count, chars: excerpt.text.count,
                             truncated: excerpt.truncated || document.pictures.count > FilePolicy.maxOCRPages,
                             via: .ocr)
    }

    private static func excerpted(_ text: String, via: ExtractionVia) -> ExtractedText {
        let excerpt = FileTextBlocks.excerpt(text, limit: FilePolicy.maxTextChars)
        return ExtractedText(text: excerpt.text, pages: nil, chars: excerpt.text.count,
                             truncated: excerpt.truncated, via: excerpt.text.isEmpty ? .none : via)
    }

    private static let pageTextMinimum = 20

    private static func extractPDF(url: URL, languages: [String]) -> ExtractedText {
        guard let document = PDFDocument(url: url) else {
            return nothing
        }
        let totalPages = document.pageCount
        let pageCount = min(totalPages, FilePolicy.maxPDFPages)
        let pageLimited = totalPages > FilePolicy.maxPDFPages
        var pages: [String] = []
        var usedOCR = false
        var ocrPages = 0
        var skippedOCR = false
        for index in 0..<pageCount {
            let page = document.page(at: index)
            let layer = (page?.string ?? "").trimmed
            guard layer.count < pageTextMinimum else {
                pages.append(layer)
                continue
            }
            guard ocrPages < FilePolicy.maxOCRPages else {
                pages.append(layer)
                skippedOCR = true
                continue
            }
            ocrPages += 1
            let scanned = render(page).flatMap {
                TextRecognizing.recognize(image: $0, languages: languages)?.trimmed
            }
            if let scanned, scanned.count > layer.count {
                pages.append(scanned)
                usedOCR = true
            } else {
                pages.append(layer)
            }
        }
        let marked = FileTextBlocks.pageMarked(pages)
        let excerpt = FileTextBlocks.excerpt(marked, limit: FilePolicy.maxTextChars)
        let via: ExtractionVia
        if usedOCR {
            via = .ocr
        } else if pages.contains(where: { !$0.isEmpty }) {
            via = .textLayer
        } else {
            via = .none
        }
        return ExtractedText(text: excerpt.text, pages: totalPages,
                             chars: excerpt.text.count,
                             truncated: excerpt.truncated || pageLimited || skippedOCR,
                             via: via)
    }

    private static func render(_ page: PDFPage?) -> UIImage? {
        guard let page else { return nil }
        let box = page.bounds(for: .mediaBox)
        let rotated = page.rotation % 180 != 0
        let width = rotated ? box.height : box.width
        let height = rotated ? box.width : box.height
        guard width > 1, height > 1 else { return nil }
        let widthScale = FilePolicy.ocrPageWidth / max(width, 1)
        let heightScale = FilePolicy.ocrPageHeight / max(height, 1)
        let pixelScale = CGFloat(sqrt(Double(FilePolicy.maxOCRPagePixels)
                                      / Double(max(width * height, 1))))
        let scale = min(min(FilePolicy.ocrRenderScale, widthScale), min(heightScale, pixelScale))
        let size = CGSize(width: max(1, width * scale), height: max(1, height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let cg = context.cgContext
            cg.saveGState()
            cg.setAlpha(1)
            cg.interpolationQuality = .high
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: scale, y: -scale)
            cg.clip(to: CGRect(origin: .zero, size: CGSize(width: width, height: height)))
            page.draw(with: .mediaBox, to: cg)
            cg.restoreGState()
        }
    }
}
