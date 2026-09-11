import XCTest
import SwiftUI
@testable import GwenMobile

@MainActor
final class UndoBarHostTests: XCTestCase {
    private func makeStage(undoWindow: Duration) throws -> (HistoryCleaner, UUID) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let paths = StoragePaths(documents: dir)
        let media = MediaStore(paths: paths)
        let store = ChatStore(media: media, paths: paths)
        let name = try XCTUnwrap(media.storeImageData(Data([1, 2, 3])))
        let conversation = try XCTUnwrap(store.current?.id)
        store.appendMessage(ChatMessage(role: .user, text: "Bild", images: [Attachment(file: name)]),
                            to: conversation)
        let cleaner = HistoryCleaner(store: store, media: media, feed: store.images,
                                     undoWindow: undoWindow)
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
