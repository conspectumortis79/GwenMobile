@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import SwiftUI
import GwenMobileKit

@MainActor
final class UndoBarHostTests: XCTestCase {
    private func makeStage(undoWindow: Duration) throws -> (HistoryCleaner, UUID) {
        let paths = StoragePaths(documents: tempDocuments())
        let media = MediaStore(paths: paths)
        let store = ChatStore(media: media, paths: paths)
        let name = try XCTUnwrap(media.storeImageData(Data([1, 2, 3])))
        let conversation = try XCTUnwrap(store.current?.id)
        store.appendMessage(ChatMessage(role: .user, text: "Bild", images: [Attachment(file: name)]),
                            to: conversation)
        let cleaner = HistoryCleaner(store: store, media: media,
                                     documents: DocumentStore(paths: paths),
                                     exports: ExportStore(paths: paths),
                                     feed: store.images, undoWindow: undoWindow)
        return (cleaner, conversation)
    }

    private func measuredHeight(of host: UIHostingController<UndoBarHost>) async throws -> CGFloat {
        try await Task.sleep(for: .milliseconds(50))
        return host.view.sizeThatFits(CGSize(width: 390, height: 1000)).height
    }

    func testBarAppearsWithoutAnyStoreChange() async throws {
        let (cleaner, conversation) = try makeStage(undoWindow: .seconds(30))
        let host = UIHostingController(rootView: UndoBarHost(cleaner: cleaner))
        let empty = try await measuredHeight(of: host)
        XCTAssertEqual(empty, 0, accuracy: 0.5)
        cleaner.deleteConversation(conversation)
        let shown = try await measuredHeight(of: host)
        XCTAssertGreaterThan(shown, 20)
    }

    func testBarCollapsesOnceTheUndoWindowExpires() async throws {
        let (cleaner, conversation) = try makeStage(undoWindow: .milliseconds(120))
        let host = UIHostingController(rootView: UndoBarHost(cleaner: cleaner))
        cleaner.deleteConversation(conversation)
        let shown = try await measuredHeight(of: host)
        XCTAssertGreaterThan(shown, 20)
        try await Task.sleep(for: .milliseconds(800))
        let expired = try await measuredHeight(of: host)
        XCTAssertEqual(expired, 0, accuracy: 0.5,
                       "der Rueckgaengig-Badge muss nach Ablauf des Fensters von selbst weg sein")
    }

    func testBarCollapsesOnUndo() async throws {
        let (cleaner, conversation) = try makeStage(undoWindow: .seconds(30))
        let host = UIHostingController(rootView: UndoBarHost(cleaner: cleaner))
        cleaner.deleteConversation(conversation)
        let shown = try await measuredHeight(of: host)
        XCTAssertGreaterThan(shown, 20)
        cleaner.undoLast()
        let undone = try await measuredHeight(of: host)
        XCTAssertEqual(undone, 0, accuracy: 0.5)
    }
}

@MainActor
final class UndoBarWordTests: XCTestCase {
    private func bar(_ receipt: DeletionReceipt) -> String {
        UndoBar(receipt: receipt, onUndo: {}).detailText
    }

    func testPicturesAreNamedPicturesAndFilesAreNamedFiles() {
        L.apply(.de)
        let mixed = DeletionReceipt(trashedFiles: [TrashedFile(file: "a.jpg", trashed: "1_a.jpg")],
                                    trashedDocuments: [TrashedFile(file: "doc_x.pdf", trashed: "2_doc_x.pdf")],
                                    freedBytes: 100, freedFiles: 2)
        let line = bar(mixed)
        XCTAssertTrue(line.contains(L.n("images_word", 1)), line)
        XCTAssertTrue(line.contains(L.n("files_word", 1)), line)
        XCTAssertFalse(line.contains("2 Bilder"), line)
    }

    func testAFileOnlyDeletionNeverClaimsPictures() {
        L.apply(.de)
        let onlyFiles = DeletionReceipt(trashedDocuments: [TrashedFile(file: "doc_x.pdf", trashed: "2_doc_x.pdf")],
                                        freedBytes: 40, freedFiles: 1)
        let line = bar(onlyFiles)
        XCTAssertTrue(line.contains(L.n("files_word", 1)), line)
        XCTAssertFalse(line.contains(L.t("images_word")), line)
    }
}
