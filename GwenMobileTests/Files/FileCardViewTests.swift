@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit

@MainActor
final class FileCardViewTests: GwenTestCase {
    private func file(kind: FileKind = .pdf, name: String = "Protokoll.pdf", bytes: Int = 240_000,
                      pages: Int? = 3, chars: Int = 12_000, truncated: Bool = false,
                      via: ExtractionVia = .ocr) -> AttachedFile {
        AttachedFile(file: "doc_card", name: name, kind: kind, bytes: bytes, pages: pages,
                     chars: chars, truncated: truncated, via: via)
    }

    func testEveryBadgeAndLabelRenders() {
        for kind in [FileKind.pdf, .rtf, .docx, .csv, .json, .text, .video] {
            XCTAssertFalse(FileGlyph.label(for: kind).isEmpty)
            XCTAssertNotNil(renderView(FileBadge(kind: kind), width: 60))
        }
    }

    func testTheStoredCardDrawsWithAndWithoutShare() async throws {
        let basic = file()
        XCTAssertNotNil(renderView(StoredFileCard(file: basic, onOpen: {}), width: 300))
        XCTAssertNotNil(renderView(StoredFileCard(file: basic, onOpen: {}, onShare: {}), width: 300))
        let controller = mountView(StoredFileCard(file: basic, onOpen: {}, onShare: {}),
                                   size: CGSize(width: 300, height: 200))
        try await settleHosted(controller)
    }

    func testTheStoredCardCoversShortAndTrimmedFiles() {
        let onePage = file(pages: 1, chars: 120, via: .textLayer)
        XCTAssertNotNil(renderView(StoredFileCard(file: onePage, onOpen: {}), width: 300))
        let trimmed = file(kind: .text, name: "lang.txt", bytes: 90_000, pages: nil, chars: 0,
                           truncated: true, via: .plain)
        XCTAssertNotNil(renderView(StoredFileCard(file: trimmed, onOpen: {}), width: 300))
        let rich = file(kind: .docx, name: "Brief.docx", bytes: 4_200, pages: 2, chars: 900, via: .richText)
        XCTAssertNotNil(renderView(StoredFileCard(file: rich, onOpen: {}), width: 300))
    }

    func testThePendingCardDrawsReadingReadyAndFailed() async throws {
        var pending = PendingFile(name: "Scan.pdf", kind: .pdf, file: "doc_p.pdf", bytes: 12_000)
        pending.reading = true
        XCTAssertNotNil(renderView(PendingFileCard(pending: pending, onRemove: {}), width: 220))
        pending.reading = false
        pending.chars = 800
        pending.pages = 2
        XCTAssertNotNil(renderView(PendingFileCard(pending: pending, onRemove: {}), width: 220))
        let controller = mountView(PendingFileCard(pending: pending, onRemove: {}),
                                   size: CGSize(width: 220, height: 120))
        try await settleHosted(controller)
        var failed = pending
        failed.failed = true
        XCTAssertNotNil(renderView(PendingFileCard(pending: failed, onRemove: {}), width: 220))
    }

    func testTheOcrCardDraws() {
        XCTAssertNotNil(renderView(OcrFileCard(entry: OcrFile(file: "ocr/scan.jpg", chars: 1_200),
                                               onOpen: {}), width: 300))
        XCTAssertNotNil(renderView(OcrFileCard(entry: OcrFile(file: "ocr/kurz.jpg", chars: 0), onOpen: {}),
                                   width: 300))
    }
}
