@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class HistoryCleanerTests: XCTestCase {
    private func makeSandbox(undoWindow: Duration? = nil)
        -> (ChatStore, HistoryCleaner, MediaStore, StoragePaths) {
        let paths = StoragePaths(documents: tempDocuments())
        let media = MediaStore(paths: paths)
        let store = ChatStore(media: media, paths: paths)
        let cleaner = undoWindow.map { HistoryCleaner(store: store, media: media,
                                                      documents: DocumentStore(paths: paths),
                                                      exports: ExportStore(paths: paths),
                                                      feed: store.images, undoWindow: $0) } ?? store.cleaner
        return (store, cleaner, media, paths)
    }

    @discardableResult
    private func attach(_ media: MediaStore, to store: ChatStore, payload: Data = Data([8, 8])) throws -> String {
        let name = try XCTUnwrap(media.storeImageData(payload))
        let id = try XCTUnwrap(store.current?.id)
        store.appendMessage(ChatMessage(role: .user, text: "Bild", images: [Attachment(file: name)]), to: id)
        return name
    }

    func testDeletingConversationTrashesUnreferencedImage() async throws {
        let (store, cleaner, media, paths) = makeSandbox()
        let name = try attach(media, to: store)
        let id = try XCTUnwrap(store.currentID)
        await cleaner.deleteConversation(id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.image(name).path))
        XCTAssertEqual(cleaner.receipt?.freedFiles, 1)
        XCTAssertFalse(store.referencedFiles.contains(name))
    }

    func testUndoRestoresConversationAndImageFile() async throws {
        let (store, cleaner, media, paths) = makeSandbox()
        let name = try attach(media, to: store)
        let id = try XCTUnwrap(store.currentID)
        await cleaner.deleteConversation(id)
        cleaner.undoLast()
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.image(name).path))
        XCTAssertEqual(store.referencedFiles, Set([name]))
        XCTAssertNil(cleaner.receipt)
    }

    func testSharedImageSurvivesWhileAnotherMessageStillReferencesIt() async throws {
        let (store, cleaner, media, paths) = makeSandbox()
        let name = try attach(media, to: store)
        let id = try XCTUnwrap(store.currentID)
        store.appendMessage(ChatMessage(role: .assistant, text: "nochmal", images: [Attachment(file: name)]), to: id)
        let first = store.conversations.first?.messages.first?.id
        await cleaner.deleteMessage(try XCTUnwrap(first), in: id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.image(name).path))
        XCTAssertEqual(cleaner.receipt?.freedFiles, 0)
    }

    func testDeleteAllRemovesEveryConversationIncludingTheOpenOne() async throws {
        let (store, cleaner, media, paths) = makeSandbox()
        let olderName = try attach(media, to: store)
        store.newConversation()
        let openName = try attach(media, to: store)
        await cleaner.deleteAllConversations()
        XCTAssertEqual(store.conversations.count, 1)
        XCTAssertEqual(store.current?.title, L.defaultTitle)
        XCTAssertEqual(store.current?.messages.count, 0)
        XCTAssertTrue(store.referencedFiles.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.image(olderName).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.image(openName).path))
    }

    func testDeleteAllRemovesCountedExportsAndUndoBringsThemBack() async throws {
        let (store, cleaner, _, paths) = makeSandbox()
        let export = paths.answers.appendingPathComponent("Antwort.html")
        try Data("antwort".utf8).write(to: export)
        let usage = StorageMeasurement.usage(conversations: store.conversations, images: store.media,
                                             documents: store.documents, exports: store.exports)
        XCTAssertEqual(usage.exportFiles, 1)
        XCTAssertEqual(usage.exportBytes, 7)
        await cleaner.deleteAllConversations()
        XCTAssertFalse(FileManager.default.fileExists(atPath: export.path))
        XCTAssertEqual(cleaner.receipt?.freedFiles, 1)
        XCTAssertEqual(cleaner.receipt?.freedBytes, 7)
        cleaner.undoLast()
        XCTAssertTrue(FileManager.default.fileExists(atPath: export.path))
    }

    func testUndoOfDeleteAllReopensThePreviousChatAndDropsTheFreshOne() async throws {
        let (store, cleaner, media, paths) = makeSandbox()
        let olderName = try attach(media, to: store)
        store.newConversation()
        let openName = try attach(media, to: store)
        let openID = try XCTUnwrap(store.currentID)
        let orderBeforeDelete = store.conversations.map(\.id)
        await cleaner.deleteAllConversations()
        let freshID = try XCTUnwrap(store.currentID)
        cleaner.undoLast()
        XCTAssertEqual(store.currentID, openID)
        XCTAssertEqual(store.conversations.map(\.id), orderBeforeDelete)
        XCTAssertFalse(store.conversations.contains { $0.id == freshID })
        XCTAssertEqual(store.referencedFiles, Set([olderName, openName]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.image(olderName).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.image(openName).path))
    }

    func testDeleteAllWithASingleChatLeavesAFreshOneAndUndoBringsItBack() async throws {
        let (store, cleaner, media, paths) = makeSandbox()
        let name = try attach(media, to: store)
        let openID = try XCTUnwrap(store.currentID)
        await cleaner.deleteAllConversations()
        XCTAssertEqual(store.conversations.count, 1)
        XCTAssertNotEqual(store.currentID, openID)
        cleaner.undoLast()
        XCTAssertEqual(store.conversations.count, 1)
        XCTAssertEqual(store.currentID, openID)
        XCTAssertEqual(store.referencedFiles, Set([name]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.image(name).path))
    }

    func testUndoOfDeletingTheOnlyChatDropsTheFreshOneAndReopensIt() async throws {
        let (store, cleaner, media, _) = makeSandbox()
        let name = try attach(media, to: store)
        let openID = try XCTUnwrap(store.currentID)
        await cleaner.deleteConversation(openID)
        let freshID = try XCTUnwrap(store.currentID)
        XCTAssertNotEqual(freshID, openID)
        cleaner.undoLast()
        XCTAssertEqual(store.conversations.map(\.id), [openID])
        XCTAssertEqual(store.currentID, openID)
        XCTAssertEqual(store.referencedFiles, Set([name]))
    }

    func testUndoKeepsAFreshChatThatReceivedAMessageMeanwhile() async throws {
        let (store, cleaner, media, _) = makeSandbox()
        try attach(media, to: store)
        let openID = try XCTUnwrap(store.currentID)
        await cleaner.deleteAllConversations()
        let freshID = try XCTUnwrap(store.currentID)
        store.appendMessage(ChatMessage(role: .user, text: "schon weiter geschrieben"), to: freshID)
        cleaner.undoLast()
        XCTAssertEqual(Set(store.conversations.map(\.id)), Set([openID, freshID]))
        XCTAssertEqual(store.currentID, freshID)
    }

    func testUndoDropsAFreshChatThatOnlyHoldsTheDeletionNotice() async throws {
        let (store, cleaner, media, _) = makeSandbox()
        try attach(media, to: store)
        let openID = try XCTUnwrap(store.currentID)
        await cleaner.deleteAllConversations()
        let freshID = try XCTUnwrap(store.currentID)
        XCTAssertNotEqual(freshID, openID)
        store.appendAssistant(L.t("history_deleted"), model: nil, elapsed: nil, to: freshID)
        cleaner.undoLast()
        XCTAssertEqual(store.currentID, openID)
        XCTAssertFalse(store.conversations.contains { $0.id == freshID })
    }

    func testDiscardingReceiptEmptiesTrashForGood() async throws {
        let (store, cleaner, media, paths) = makeSandbox()
        try attach(media, to: store)
        await cleaner.deleteConversation(try XCTUnwrap(store.currentID))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: paths.trash.path).isEmpty)
        cleaner.discardPendingDeletion()
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: paths.trash.path).isEmpty)
        XCTAssertNil(cleaner.receipt)
    }

    func testSecondDeletionKeepsTheFirstUndoWindowOpen() async throws {
        let (store, cleaner, media, paths) = makeSandbox()
        let first = try attach(media, to: store)
        let firstID = try XCTUnwrap(store.currentID)
        await cleaner.deleteConversation(firstID)
        store.newConversation()
        let second = try attach(media, to: store)
        await cleaner.deleteConversation(try XCTUnwrap(store.currentID))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.image(first).path))
        XCTAssertTrue(cleaner.receipt?.trashedFiles.contains(where: { $0.file == second }) ?? false)
        cleaner.undoLast()
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.image(second).path))
        XCTAssertTrue(cleaner.receipt?.trashedFiles.contains(where: { $0.file == first }) ?? false,
                      "beide Löschungen warten auf ihr eigenes Fenster")
        cleaner.undoLast()
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.image(first).path))
        XCTAssertNil(cleaner.receipt)
        XCTAssertEqual(store.referencedFiles, Set([first, second]))
    }

    func testUnmovablePicturesAreNotCountedAsFreed() async throws {
        let (store, cleaner, _, _) = makeSandbox()
        let id = try XCTUnwrap(store.current?.id)
        store.appendMessage(ChatMessage(role: .user, text: "Verlust", images: [Attachment(file: "fehit.jpg")]),
                            to: id)
        await cleaner.deleteConversation(id)
        XCTAssertEqual(cleaner.receipt?.freedFiles, 0)
        XCTAssertEqual(cleaner.receipt?.freedBytes, 0)
        XCTAssertTrue(cleaner.receipt?.trashedFiles.isEmpty ?? false)
    }

    func testAFailedConversationSaveKeepsTheMessageAndTheFile() async throws {
        let paths = StoragePaths(documents: tempDocuments())
        let media = MediaStore(paths: paths)
        media.prepareDirectories()
        let name = try XCTUnwrap(media.storeImageData(Data([1, 2, 3])))
        let conversation = Conversation(title: "Test", messages: [
            ChatMessage(role: .user, text: "Bild", images: [Attachment(file: name)])
        ])
        let store = ChatStore(media: media, paths: paths,
                              persistence: FailingPersistence(conversations: [conversation]))
        let cleaner = HistoryCleaner(store: store, media: media,
                                     documents: DocumentStore(paths: paths),
                                     exports: ExportStore(paths: paths),
                                     feed: store.images)
        await cleaner.deleteMessage(conversation.messages[0].id, in: conversation.id)
        XCTAssertTrue(media.hasImage(name))
        XCTAssertEqual(store.current?.messages.count, 1)
        XCTAssertNil(cleaner.receipt)
        XCTAssertNotNil(store.storageProblem)
    }

    func testTrashedFilesThatAreStillReferencedComeBackOnLoad() throws {
        let paths = StoragePaths(documents: tempDocuments())
        let media = MediaStore(paths: paths)
        media.prepareDirectories()
        let name = try XCTUnwrap(media.storeImageData(Data([1, 2, 3])))
        let conversation = Conversation(title: "Test", messages: [
            ChatMessage(role: .user, text: "Bild", images: [Attachment(file: name)])
        ])
        XCTAssertEqual(media.moveImagesToTrash([name]).count, 1)
        let store = ChatStore(media: media, paths: paths,
                              persistence: StaticPersistence(conversations: [conversation]))
        XCTAssertTrue(media.hasImage(name))
        XCTAssertEqual(store.current?.messages.count, 1)
    }

    func testUndoWindowExpiresTheReceiptOnItsOwn() async throws {
        let (store, cleaner, media, paths) = makeSandbox(undoWindow: .milliseconds(60))
        let name = try attach(media, to: store)
        await cleaner.deleteConversation(try XCTUnwrap(store.currentID))
        XCTAssertNotNil(cleaner.receipt)
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertNil(cleaner.receipt)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: paths.trash.path).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.image(name).path))
    }

    func testUndoInsideTheWindowCancelsTheAutomaticExpiry() async throws {
        let (store, cleaner, media, paths) = makeSandbox(undoWindow: .milliseconds(60))
        let name = try attach(media, to: store)
        await cleaner.deleteConversation(try XCTUnwrap(store.currentID))
        cleaner.undoLast()
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.image(name).path))
        XCTAssertEqual(store.referencedFiles, Set([name]))
        XCTAssertNil(cleaner.receipt)
    }

    func testMeasurementCountsFilesBytesAndPerConversationShare() async throws {
        let (store, _, media, _) = makeSandbox()
        let name = try attach(media, to: store)
        let usage = StorageMeasurement.usage(conversations: store.conversations, images: media)
        XCTAssertEqual(usage.conversations, 1)
        XCTAssertEqual(usage.messages, 1)
        XCTAssertEqual(usage.imageFiles, 1)
        XCTAssertEqual(usage.imageBytes, 2)
        XCTAssertEqual(usage.bytesByConversation[try XCTUnwrap(store.currentID)], 2)
        XCTAssertTrue(name.hasPrefix("img_"))
    }

    func testConversationSizeCountsGalleryAndSharedFilesOnce() async throws {
        let (store, _, media, _) = makeSandbox()
        let shared = try attach(media, to: store, payload: Data([1, 1]))
        let id = try XCTUnwrap(store.currentID)
        store.appendMessage(ChatMessage(role: .assistant, text: "nochmal",
                                        images: [Attachment(file: shared)]), to: id)
        let galleryFile = try XCTUnwrap(media.storeImageData(Data([2, 2, 2])))
        let picture = WebPicture(file: galleryFile, pageURL: "https://example.test/a",
                                 fullURL: "https://example.test/a.jpg", title: "A", domain: "example.test")
        let gallery = PictureGallery(query: "A", pictures: [picture], shown: 1,
                                     nextOffset: 2, exhausted: true)
        store.appendMessage(ChatMessage(role: .assistant, text: "", gallery: gallery), to: id)
        let usage = StorageMeasurement.usage(conversations: store.conversations, images: media)
        XCTAssertEqual(usage.bytesByConversation[id], 5)
    }

    func testDeletionMeasuresTheRemainingHistoryInsteadOfWipingTheNumbers() async throws {
        let (store, cleaner, media, _) = makeSandbox()
        try attach(media, to: store)
        store.newConversation()
        try attach(media, to: store)
        await cleaner.refreshUsage()
        let kept = try XCTUnwrap(store.conversations.first { $0.id != store.currentID }?.id)
        XCTAssertEqual(cleaner.usage.bytesByConversation[kept], 2)
        await cleaner.deleteConversation(try XCTUnwrap(store.currentID))
        await waitUntil { cleaner.usage.conversations == 1
            && cleaner.usage.bytesByConversation[kept] == 2
            && cleaner.usage.messages == 1 }
        XCTAssertEqual(cleaner.usage.imageFiles, 1)
        XCTAssertEqual(cleaner.usage.imageBytes, 2)
    }

    func testUnknownIdsAndEmptyPendingStacksAreIgnored() async {
        let (store, cleaner, _, _) = makeSandbox()
        let unknown = UUID()
        await cleaner.deleteMessage(UUID(), in: unknown)
        XCTAssertNil(cleaner.receipt)
        await cleaner.deleteConversation(unknown)
        XCTAssertNil(cleaner.receipt)
        cleaner.undoLast()
        cleaner.discardPendingDeletion()
        XCTAssertNil(cleaner.receipt)
        XCTAssertNotNil(store.current)
    }

    func testAFailedConversationDeleteRestoresItAndThePlaceholder() async throws {
        let paths = StoragePaths(documents: tempDocuments())
        let media = MediaStore(paths: paths)
        media.prepareDirectories()
        let conversation = Conversation(title: "Test", messages: [ChatMessage(role: .user, text: "Hallo")])
        let store = ChatStore(media: media, paths: paths,
                              persistence: FailingPersistence(conversations: [conversation]))
        let cleaner = HistoryCleaner(store: store, media: media,
                                     documents: DocumentStore(paths: paths),
                                     exports: ExportStore(paths: paths), feed: store.images)
        await cleaner.deleteConversation(conversation.id)
        XCTAssertEqual(store.conversations.map(\.id), [conversation.id])
        XCTAssertEqual(store.currentID, conversation.id)
        XCTAssertNil(cleaner.receipt)
    }

    func testAFailedDeleteAllRestoresEveryConversation() async throws {
        let paths = StoragePaths(documents: tempDocuments())
        let media = MediaStore(paths: paths)
        media.prepareDirectories()
        let first = Conversation(title: "Erster", messages: [])
        let second = Conversation(title: "Zweiter", messages: [])
        let store = ChatStore(media: media, paths: paths,
                              persistence: FailingPersistence(conversations: [first, second]))
        let cleaner = HistoryCleaner(store: store, media: media,
                                     documents: DocumentStore(paths: paths),
                                     exports: ExportStore(paths: paths), feed: store.images)
        await cleaner.deleteAllConversations()
        XCTAssertEqual(Set(store.conversations.map(\.id)), Set([first.id, second.id]))
        XCTAssertNil(cleaner.receipt)
    }
}

private struct FailingPersistence: ConversationPersisting, @unchecked Sendable {
    let conversations: [Conversation]

    func persist(_ conversations: [Conversation]) async throws {
        throw APIError(message: "kaputt")
    }

    func load() -> ConversationLoad {
        .loaded(conversations)
    }
}

private struct StaticPersistence: ConversationPersisting, @unchecked Sendable {
    let conversations: [Conversation]

    func persist(_ conversations: [Conversation]) async throws {}

    func load() -> ConversationLoad {
        .loaded(conversations)
    }
}
