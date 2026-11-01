import GwenMobileKit
import UIKit

struct ScanOutcome: Equatable, Sendable {
    var attachment: AttachedFile
    var text: String
}

typealias ScanRecognizing = @Sendable (UIImage, [String]) -> String?

struct ScanWorkflow {
    static let pageSize = CGSize(width: 595, height: 842)
    static let pageMargin: CGFloat = 18

    var recognize: ScanRecognizing = { TextRecognizing.recognize(image: $0, languages: $1) }

    func store(pages: [UIImage], kind: ScanKind, date: Date,
               documents: DocumentStore) -> ScanOutcome? {
        let limited = Array(pages.prefix(FilePolicy.maxPDFPages))
        guard !limited.isEmpty else { return nil }
        let excerpt = FileTextBlocks.excerpt(recognizedText(limited), limit: FilePolicy.maxTextChars)
        let text = excerpt.text
        let truncated = excerpt.truncated || limited.count < pages.count
        guard let data = pdfData(pages: limited) else { return nil }
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan_\(UUID().uuidString).pdf")
        guard (try? data.write(to: temporary)) != nil,
              let stored = documents.store(url: temporary) else {
            try? FileManager.default.removeItem(at: temporary)
            return nil
        }
        try? FileManager.default.removeItem(at: temporary)
        if !text.isEmpty { documents.writeText(text, for: stored.file) }
        flowMark("SCAN pdf bytes=\(stored.bytes) seiten=\(limited.count)/\(pages.count) "
                 + "zeichen=\(text.count) gekuerzt=\(truncated)")
        let attachment = AttachedFile(file: stored.file,
                                      name: ScanAnswers.fileName(for: kind, date: date),
                                      kind: .pdf,
                                      bytes: stored.bytes,
                                      pages: limited.count,
                                      chars: text.count,
                                      truncated: truncated,
                                      via: text.isEmpty ? .none : .ocr)
        ScanSaver.storeInDownloads(attachment, documents: documents)
        return ScanOutcome(attachment: attachment, text: text)
    }

    private func recognizedText(_ pages: [UIImage]) -> String {
        let languages = TextRecognizing.languages
        let lines = pages.map { page in
            recognize(page, languages)?.trimmed ?? ""
        }
        return FileTextBlocks.pageMarked(lines).trimmed
    }

    private func pdfData(pages: [UIImage]) -> Data? {
        let bounds = CGRect(origin: .zero, size: Self.pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { context in
            for page in pages {
                context.beginPage()
                UIColor.white.setFill()
                context.fill(bounds)
                page.draw(in: Self.fitted(page.size, in: bounds.insetBy(dx: Self.pageMargin,
                                                                        dy: Self.pageMargin)))
            }
        }
    }

    static func fitted(_ size: CGSize, in box: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return box }
        let scale = min(box.width / size.width, box.height / size.height)
        let width = size.width * scale
        let height = size.height * scale
        return CGRect(x: box.midX - width / 2, y: box.midY - height / 2, width: width, height: height)
    }
}
