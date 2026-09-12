import XCTest
@testable import GwenMobile

@MainActor
final class ChatStoreTests: XCTestCase {
    private func makeSandbox() -> (ChatStore, StoragePaths) {
        makeSandbox(at: StoragePaths(documents: tempDocuments()))
    }

    private func makeSandbox(at paths: StoragePaths) -> (ChatStore, StoragePaths) {
        (ChatStore(media: MediaStore(paths: paths), paths: paths), paths)
    }

    func testUnwritableStoreReportsAStorageProblem() async throws {
        let paths = StoragePaths(documents: tempDocuments())
        try FileManager.default.createDirectory(at: paths.conversations, withIntermediateDirectories: true)
        let (store, _) = makeSandbox(at: paths)
        XCTAssertNil(store.storageProblem)
        store.newConversation()
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertEqual(store.storageProblem, L.t("storage_save_failed"))
    }

    func testInitStartsWithOneFreshConversation() {
        let (store, _) = makeSandbox()
        XCTAssertEqual(store.conversations.count, 1)
        XCTAssertEqual(store.current?.title, L.defaultTitle)
        XCTAssertEqual(store.currentID, store.conversations.first?.id)
    }

    func testNewConversationIsPrependedAndBecomesCurrent() {
        let (store, _) = makeSandbox()
        let previous = store.currentID
        store.newConversation()
        XCTAssertEqual(store.conversations.count, 2)
        XCTAssertNotEqual(store.currentID, previous)
        XCTAssertEqual(store.current?.messages.count, 0)
    }

    func testFirstUserMessageBecomesTheConversationTitle() throws {
        let (store, _) = makeSandbox()
        let id = try XCTUnwrap(store.current?.id)
        store.appendMessage(ChatMessage(role: .user, text: "Zahnarzt morgen um zehn"), to: id)
        XCTAssertEqual(store.current?.title, "Zahnarzt morgen um zehn")
    }

    func testLongFirstUserMessageIsCutForTheTitle() throws {
        let (store, _) = makeSandbox()
        let id = try XCTUnwrap(store.current?.id)
        store.appendMessage(ChatMessage(role: .user, text: String(repeating: "a", count: 90)), to: id)
        XCTAssertEqual(store.current?.title.count, 40)
    }

    func testCustomTitleSurvivesLaterMessages() throws {
        let (store, _) = makeSandbox()
        let id = try XCTUnwrap(store.current?.id)
        store.appendMessage(ChatMessage(role: .user, text: "Anfang"), to: id)
        store.appendMessage(ChatMessage(role: .user, text: "Weitere Frage"), to: id)
        XCTAssertEqual(store.current?.title, "Anfang")
    }

    func testAssistantHelperKeepsModelElapsedAndPayloads() throws {
        let (store, _) = makeSandbox()
        let id = try XCTUnwrap(store.current?.id)
        let image = Attachment(file: "img_test.jpg")
        let source = WebSource(title: "T", url: "https://t.example", domain: "t.example")
        store.appendAssistant("Antwort", model: "qwen3.8-flash", elapsed: 1.5, to: id,
                              outImages: [image], sources: [source], thinking: .medium)
        let message = try XCTUnwrap(store.current?.messages.last)
        XCTAssertEqual(message.text, "Antwort")
        XCTAssertEqual(message.model, "qwen3.8-flash")
        XCTAssertEqual(message.elapsed, 1.5)
        XCTAssertEqual(message.outImages, [image])
        XCTAssertEqual(message.sources, [source])
        XCTAssertEqual(message.thinking, .medium)
    }

    func testThinkingLevelIsPersistedAndOldMessagesWithoutItStillLoad() async throws {
        let (store, paths) = makeSandbox()
        let id = try XCTUnwrap(store.current?.id)
        store.appendAssistant("mit denktiefe", model: "qwen3.8-flash", elapsed: 2.5, to: id,
                              thinking: .off)
        store.appendAssistant("ohne denktiefe", model: "qwen3.8-flash", elapsed: 1.0, to: id)
        try await Task.sleep(for: .milliseconds(700))
        let reloaded = ChatStore(media: MediaStore(paths: paths), paths: paths)
        let messages = try XCTUnwrap(reloaded.conversations.first?.messages)
        XCTAssertEqual(messages.map(\.thinking), [.off, nil])
    }

    func testRemoveConversationReturnsIndexAndConversation() throws {
        let (store, _) = makeSandbox()
        store.newConversation()
        let id = try XCTUnwrap(store.currentID)
        let removed = try XCTUnwrap(store.removeConversation(id))
        XCTAssertEqual(removed.conversation.id, id)
        XCTAssertEqual(store.conversations.count, 1)
    }

    func testReferencedFilesListsEveryAttachment() throws {
        let (store, _) = makeSandbox()
        let id = try XCTUnwrap(store.current?.id)
        store.appendMessage(ChatMessage(role: .user, text: "Bild", images: [Attachment(file: "a.jpg")]), to: id)
        store.appendAssistant("Ergebnis", model: nil, elapsed: nil, to: id, outImages: [Attachment(file: "b.jpg")])
        XCTAssertEqual(store.referencedFiles, Set(["a.jpg", "b.jpg"]))
    }

    func testRemovingCurrentConversationSelectsAnotherOne() throws {
        let (store, _) = makeSandbox()
        let first = try XCTUnwrap(store.currentID)
        store.newConversation()
        let second = try XCTUnwrap(store.currentID)
        store.removeConversation(second)
        XCTAssertEqual(store.currentID, first)
    }

    func testRemovingTheLastConversationCreatesAFreshOne() throws {
        let (store, _) = makeSandbox()
        store.removeConversation(try XCTUnwrap(store.currentID))
        XCTAssertEqual(store.conversations.count, 1)
        XCTAssertEqual(store.current?.title, L.defaultTitle)
    }

    func testRemoveAllConversationsLeavesOneFreshChat() throws {
        let (store, _) = makeSandbox()
        let previousID = try XCTUnwrap(store.currentID)
        store.newConversation()
        let removed = store.removeAllConversations()
        XCTAssertEqual(removed.count, 2)
        XCTAssertEqual(store.conversations.count, 1)
        XCTAssertFalse(store.conversations.contains { $0.id == previousID })
        XCTAssertEqual(store.current?.title, L.defaultTitle)
        XCTAssertEqual(store.current?.messages.count, 0)
        XCTAssertEqual(store.currentID, store.conversations.first?.id)
    }

    func testFlushPendingSaveWritesBeforeTheDebounceElapses() throws {
        let (store, paths) = makeSandbox()
        let id = try XCTUnwrap(store.current?.id)
        store.appendMessage(ChatMessage(role: .user, text: "Frage"), to: id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.conversations.path))
        store.flushPendingSave()
        let data = try XCTUnwrap(FileManager.default.contents(atPath: paths.conversations.path))
        let reloaded = try JSONDecoder().decode([Conversation].self, from: data)
        XCTAssertEqual(reloaded.first?.messages.count, 1)
    }

    func testConversationsArePersistedAndReloadedSortedByUpdate() async throws {
        let (store, paths) = makeSandbox()
        let id = try XCTUnwrap(store.current?.id)
        store.appendMessage(ChatMessage(role: .user, text: "Frage"), to: id)
        store.newConversation()
        try await Task.sleep(for: .milliseconds(600))
        let reloaded = ChatStore(media: MediaStore(paths: paths), paths: paths)
        XCTAssertEqual(reloaded.conversations.count, 2)
        XCTAssertEqual(reloaded.conversations.first?.messages.count, 0)
        XCTAssertEqual(reloaded.conversations.last?.messages.count, 1)
    }
}
