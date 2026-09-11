import XCTest
@testable import GwenMobile

@MainActor
final class HistoryCleanerTests: XCTestCase {
    private func makeSandbox(undoWindow: Duration? = nil)
        -> (ChatStore, HistoryCleaner, MediaStore, StoragePaths) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let paths = StoragePaths(documents: dir)
        let media = MediaStore(paths: paths)
        let store = ChatStore(media: media, paths: paths)
        let cleaner = undoWindow.map { HistoryCleaner(store: store, media: media, feed: store.images,
                                                      undoWindow: $0) } ?? store.cleaner
        return (store, cleaner, media, paths)
    }

    @discardableResult
    private func attach(_ media: MediaStore, to store: ChatStore, payload: Data = Data([8, 8])) throws -> String {
        let name = try XCTUnwrap(media.storeImageData(payload))
        let id = try XCTUnwrap(store.current?.id)
        store.appendMessage(ChatMessage(role: .user, text: "Bild", images: [Attachment(file: name)]), to: id)
        return name
    }

    func testDeletingConversationTrashesUnreferencedImage() throws {
        let (store, cleaner, media, paths) = makeSandbox()
        let name = try attach(media, to: store)
        let id = try XCTUnwrap(store.currentID)
        cleaner.deleteConversation(id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.image(name).path))
        XCTAssertEqual(cleaner.receipt?.freedFiles, 1)
        XCTAssertFalse(store.referencedFiles.contains(name))
    }

    func testUndoRestoresConversationAndImageFile() throws {
        let (store, cleaner, media, paths) = makeSandbox()
        let name = try attach(media, to: store)
        let id = try XCTUnwrap(store.currentID)
        cleaner.deleteConversation(id)
        cleaner.undoLast()
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.image(name).path))
        XCTAssertEqual(store.referencedFiles, Set([name]))
        XCTAssertNil(cleaner.receipt)
    }

    func testSharedImageSurvivesWhileAnotherMessageStillReferencesIt() throws {
        let (store, cleaner, media, paths) = makeSandbox()
        let name = try attach(media, to: store)
        let id = try XCTUnwrap(store.currentID)
        store.appendMessage(ChatMessage(role: .assistant, text: "nochmal", images: [Attachment(file: name)]), to: id)
        let first = store.conversations.first?.messages.first?.id
        cleaner.deleteMessage(try XCTUnwrap(first), in: id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.image(name).path))
        XCTAssertEqual(cleaner.receipt?.freedFiles, 0)
    }

    func testDeleteAllRemovesEveryConversationIncludingTheOpenOne() throws {
        let (store, cleaner, media, paths) = makeSandbox()
        let olderName = try attach(media, to: store)
        store.newConversation()
        let openName = try attach(media, to: store)
        cleaner.deleteAllConversations()
        XCTAssertEqual(store.conversations.count, 1)
        XCTAssertEqual(store.current?.title, L.defaultTitle)
        XCTAssertEqual(store.current?.messages.count, 0)
        XCTAssertTrue(store.referencedFiles.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.image(olderName).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.image(openName).path))
    }

    func testUndoOfDeleteAllReopensThePreviousChatAndDropsTheFreshOne() throws {
        let (store, cleaner, media, paths) = makeSandbox()
        let olderName = try attach(media, to: store)
        store.newConversation()
        let openName = try attach(media, to: store)
        let openID = try XCTUnwrap(store.currentID)
        let orderBeforeDelete = store.conversations.map(\.id)
        cleaner.deleteAllConversations()
        let freshID = try XCTUnwrap(store.currentID)
        cleaner.undoLast()
        XCTAssertEqual(store.currentID, openID)
        XCTAssertEqual(store.conversations.map(\.id), orderBeforeDelete)
        XCTAssertFalse(store.conversations.contains { $0.id == freshID })
        XCTAssertEqual(store.referencedFiles, Set([olderName, openName]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.image(olderName).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.image(openName).path))
    }

    func testDeleteAllWithASingleChatLeavesAFreshOneAndUndoBringsItBack() throws {
        let (store, cleaner, media, paths) = makeSandbox()
        let name = try attach(media, to: store)
        let openID = try XCTUnwrap(store.currentID)
        cleaner.deleteAllConversations()
        XCTAssertEqual(store.conversations.count, 1)
        XCTAssertNotEqual(store.currentID, openID)
        cleaner.undoLast()
        XCTAssertEqual(store.conversations.count, 1)
        XCTAssertEqual(store.currentID, openID)
        XCTAssertEqual(store.referencedFiles, Set([name]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.image(name).path))
    }

    func testDiscardingReceiptEmptiesTrashForGood() throws {
        let (store, cleaner, media, paths) = makeSandbox()
        let name = try attach(media, to: store)
        cleaner.deleteConversation(try XCTUnwrap(store.currentID))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: paths.trash.path).isEmpty)
        cleaner.discardPendingDeletion()
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: paths.trash.path).isEmpty)
        XCTAssertNil(cleaner.receipt)
    }

    func testNextDeletionDiscardsThePreviousUndoWindow() throws {
        let (store, cleaner, media, paths) = makeSandbox()
        let first = try attach(media, to: store)
        let firstID = try XCTUnwrap(store.currentID)
        cleaner.deleteConversation(firstID)
        store.newConversation()
        let second = try attach(media, to: store)
        cleaner.deleteConversation(try XCTUnwrap(store.currentID))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.image(first).path))
        XCTAssertTrue(cleaner.receipt?.trashedFiles.contains(where: { $0.hasSuffix(second) }) ?? false)
    }

    func testUndoWindowExpiresTheReceiptOnItsOwn() async throws {
        let (store, cleaner, media, paths) = makeSandbox(undoWindow: .milliseconds(60))
        let name = try attach(media, to: store)
        cleaner.deleteConversation(try XCTUnwrap(store.currentID))
        XCTAssertNotNil(cleaner.receipt)
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertNil(cleaner.receipt)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: paths.trash.path).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.image(name).path))
    }

    func testUndoInsideTheWindowCancelsTheAutomaticExpiry() async throws {
        let (store, cleaner, media, paths) = makeSandbox(undoWindow: .milliseconds(60))
        let name = try attach(media, to: store)
        cleaner.deleteConversation(try XCTUnwrap(store.currentID))
        cleaner.undoLast()
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.image(name).path))
        XCTAssertEqual(store.referencedFiles, Set([name]))
        XCTAssertNil(cleaner.receipt)
    }

    func testMeasurementCountsFilesBytesAndPerConversationShare() throws {
        let (store, _, media, _) = makeSandbox()
        let name = try attach(media, to: store)
        let usage = StorageMeasurement.usage(conversations: store.conversations, inventory: media)
        XCTAssertEqual(usage.conversations, 1)
        XCTAssertEqual(usage.messages, 1)
        XCTAssertEqual(usage.imageFiles, 1)
        XCTAssertEqual(usage.imageBytes, 2)
        XCTAssertEqual(usage.bytesByConversation[try XCTUnwrap(store.currentID)], 2)
        XCTAssertTrue(name.hasPrefix("img_"))
    }
}
