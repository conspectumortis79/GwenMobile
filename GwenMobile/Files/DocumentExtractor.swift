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
    static func extract(url: URL, kind: FileKind, ocrLanguages: [String]) -> ExtractedText {
        switch kind {
        case .pdf:
            return extractPDF(url: url, languages: ocrLanguages)
        case .rtf:
            return extractRichText(url: url, languages: ocrLanguages)
        case .docx:
            return extractWordDocument(url: url)
        case .video:
            return ExtractedText(text: "", pages: nil, chars: 0, truncated: false, via: .none)
        case .text, .csv, .json:
            guard let data = try? Data(contentsOf: url) else {
                return ExtractedText(text: "", pages: nil, chars: 0, truncated: false, via: .none)
            }
            let excerpt = FileTextBlocks.excerpt(PlainTextDecoding.text(of: data), limit: FilePolicy.maxTextChars)
            return ExtractedText(text: excerpt.text, pages: nil, chars: excerpt.text.count,
                                 truncated: excerpt.truncated, via: .plain)
        }
    }

    private static func extractWordDocument(url: URL) -> ExtractedText {
        guard let data = try? Data(contentsOf: url),
              let text = DocxText.text(from: data) else {
            return ExtractedText(text: "", pages: nil, chars: 0, truncated: false, via: .none)
        }
        let excerpt = FileTextBlocks.excerpt(text, limit: FilePolicy.maxTextChars)
        return ExtractedText(text: excerpt.text, pages: nil, chars: excerpt.text.count,
                             truncated: excerpt.truncated, via: excerpt.text.isEmpty ? .none : .docx)
    }

    private static func extractRichText(url: URL, languages: [String]) -> ExtractedText {
        let document = RichTextFile.read(url: url)
        guard document.hasPictures else { return richTextExcerpt(document.text) }
        var scanned: [String] = []
        for picture in document.pictures.prefix(FilePolicy.maxOCRPages) {
            guard let text = TextRecognizing.recognize(data: picture, languages: languages) else { continue }
            scanned.append(text)
        }
        guard !scanned.isEmpty else { return richTextExcerpt(document.text) }
        let parts = [richTextExcerpt(document.text).text, FileTextBlocks.pageMarked(scanned)]
            .filter { !$0.isEmpty }
        let excerpt = FileTextBlocks.excerpt(parts.joined(separator: "\n\n"),
                                             limit: FilePolicy.maxTextChars)
        return ExtractedText(text: excerpt.text, pages: scanned.count, chars: excerpt.text.count,
                             truncated: excerpt.truncated, via: .ocr)
    }

    private static func richTextExcerpt(_ text: String) -> ExtractedText {
        let excerpt = FileTextBlocks.excerpt(text, limit: FilePolicy.maxTextChars)
        return ExtractedText(text: excerpt.text, pages: nil, chars: excerpt.text.count,
                             truncated: excerpt.truncated, via: excerpt.text.isEmpty ? .none : .richText)
    }

    private static func extractPDF(url: URL, languages: [String]) -> ExtractedText {
        guard let document = PDFDocument(url: url) else {
            return ExtractedText(text: "", pages: nil, chars: 0, truncated: false, via: .none)
        }
        let pageCount = min(document.pageCount, FilePolicy.maxPDFPages)
        var pages: [String] = []
        for index in 0..<pageCount {
            let body = document.page(at: index)?.string ?? ""
            pages.append(body.trimmed)
        }
        let textChars = pages.reduce(0) { $0 + $1.count }
        let filledPages = pages.filter { !$0.isEmpty }.count
        let requiredPages = max(1, (pageCount + 2) / 3)
        if textChars >= FilePolicy.ocrMinChars, filledPages >= requiredPages {
            let marked = FileTextBlocks.pageMarked(pages)
            let excerpt = FileTextBlocks.excerpt(marked, limit: FilePolicy.maxTextChars)
            return ExtractedText(text: excerpt.text, pages: pages.count,
                                 chars: excerpt.text.count, truncated: excerpt.truncated,
                                 via: .textLayer)
        }
        return ocrPDF(document, pages: pageCount, languages: languages)
    }

    private static func ocrPDF(_ document: PDFDocument, pages pageCount: Int,
                               languages: [String]) -> ExtractedText {
        var lines: [String] = []
        for index in 0..<min(pageCount, FilePolicy.maxOCRPages) {
            guard let image = render(document.page(at: index)),
                  let text = TextRecognizing.recognize(image: image, languages: languages) else { continue }
            lines.append(text)
        }
        let joined = lines.joined(separator: "\n\n").trimmed
        let excerpt = FileTextBlocks.excerpt(joined, limit: FilePolicy.maxTextChars)
        return ExtractedText(text: excerpt.text, pages: lines.isEmpty ? nil : lines.count,
                             chars: excerpt.text.count,
                             truncated: excerpt.truncated, via: excerpt.text.isEmpty ? .none : .ocr)
    }

    private static func render(_ page: PDFPage?) -> UIImage? {
        guard let page else { return nil }
        let box = page.bounds(for: .mediaBox)
        guard box.width > 1, box.height > 1 else { return nil }
        let scale = min(FilePolicy.ocrRenderScale,
                        FilePolicy.ocrPageWidth / max(box.width, 1))
        let size = CGSize(width: box.width * scale, height: box.height * scale)
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
            cg.clip(to: CGRect(origin: .zero, size: box.size))
            page.draw(with: .mediaBox, to: cg)
            cg.restoreGState()
        }
    }
}
