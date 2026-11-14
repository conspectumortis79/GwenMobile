import GwenMobileKit
import Foundation

enum FileTextBlocks {
    static var fileHead: String { PromptLibrary.text("file_block_head") }
    static var fileEnd: String { PromptLibrary.text("file_block_end") }
    static var pageMarker: String { PromptLibrary.text("file_page_marker") }

    static func excerpt(_ text: String, limit: Int) -> (text: String, truncated: Bool) {
        let trimmed = text.trimmed
        guard trimmed.count > limit else { return (trimmed, false) }
        return (String(trimmed.prefix(limit)), true)
    }

    static func file(name: String, pages: Int?, text: String, via: ExtractionVia,
                     truncated: Bool) -> String {
        var head = fileHead + " " + name
        switch via {
        case .textLayer:
            head += " " + (pages.map { PromptLibrary.text("file_detail_text_layer_pages",
                                                          ["pages": String($0)]) }
                ?? PromptLibrary.text("file_detail_text_layer"))
        case .richText:
            head += " " + PromptLibrary.text("file_detail_rich_text")
        case .docx:
            head += " " + PromptLibrary.text("file_detail_docx")
        case .ocr:
            head += " " + (pages.map { PromptLibrary.text("file_detail_ocr_pages",
                                                          ["pages": String($0)]) }
                ?? PromptLibrary.text("file_detail_ocr"))
        case .plain:
            head += " " + PromptLibrary.text("file_detail_plain")
        case .none:
            head += " " + PromptLibrary.text("file_detail_none")
        }
        if truncated { head += " " + PromptLibrary.text("file_trimmed_note") }
        return head + "\n" + text + "\n" + fileEnd
    }

    static func pageMarked(_ pages: [String]) -> String {
        guard pages.count > 1 else { return pages.first ?? "" }
        return pages.enumerated()
            .map { "\(pageMarker) \($0.offset + 1) ---\n\($0.element)" }
            .joined(separator: "\n")
    }

    static func joinedWithinBudget<Element>(_ blocks: [Element], budget: Int,
                                            size: (Element) -> Int,
                                            block: (Element) -> String)
        -> (text: String, kept: [Element], dropped: Int) {
        var kept: [Element] = []
        var used = 0
        var dropped = 0
        for entry in blocks.reversed() {
            let size = size(entry)
            if used + size > budget {
                dropped += 1
                continue
            }
            used += size
            kept.insert(entry, at: 0)
        }
        return (kept.map(block).joined(separator: "\n\n"), kept, dropped)
    }

    static func omittedNotice(_ count: Int) -> String {
        "(" + PromptLibrary.text("file_omitted_notice", ["count": String(count)]) + ")"
    }
}
