@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class ChatStoreTests: XCTestCase {
    private func makeSandbox() -> (ChatStore, StoragePaths) {
        makeSandbox(at: StoragePaths(documents: tempDocuments()))
    }

    private func makeSandbox(at paths: StoragePaths) -> (ChatStore, StoragePaths) {
        (ChatStore(media: MediaStore(paths: paths), paths: paths), paths)
    }

    private func storedConversations(at paths: StoragePaths) throws -> [Conversation] {
        let persistence = ConversationFolderPersistence(
            folder: paths.conversationsFolder,
            legacy: ConversationFilePersistence(url: paths.conversations))
        return try XCTUnwrap(persistence.load().conversations, "die Historie muss in der Ablage liegen")
    }

    func testUnwritableStoreReportsAStorageProblem() async throws {
        let paths = StoragePaths(documents: tempDocuments())
        try FileManager.default.createDirectory(at: paths.support, withIntermediateDirectories: true)
        try Data([0]).write(to: paths.conversationsFolder)
        let (store, _) = makeSandbox(at: paths)
        XCTAssertNil(store.storageProblem)
        store.newConversation()
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertEqual(store.storageProblem, L.t("storage_save_failed"))
    }

    func testAMemoryStoreFailureReportsAStorageProblemThatSurvivesAConversationSave() async throws {
        let paths = StoragePaths(documents: tempDocuments())
        let (store, _) = makeSandbox(at: paths)
        try await Task.sleep(for: .milliseconds(700))
        try FileManager.default.createDirectory(at: paths.support, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500],
                                              ofItemAtPath: paths.support.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700],
                                                   ofItemAtPath: paths.support.path)
        }
        try await Task.sleep(for: .milliseconds(50))
        await store.memory.add(text: "Erster Eintrag", category: .likes, source: .explicit)
        await waitUntil { store.storageProblem != nil }
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(store.storageProblem, L.t("storage_save_failed"))
    }

    func testInitStartsWithOneFreshConversation() {
        let (store, _) = makeSandbox()
        XCTAssertEqual(store.conversations.count, 1)
        XCTAssertEqual(store.current?.title, L.defaultTitle)
        XCTAssertEqual(store.currentID, store.conversations.first?.id)
    }

    func testARecoveredHistoryWarnsInsteadOfLookingIntact() async throws {
        let paths = StoragePaths(documents: tempDocuments())
        let persistence = ConversationFilePersistence(url: paths.conversations)
        var conversation = Conversation(title: "Zahnarzt")
        conversation.messages = [ChatMessage(role: .user, text: "Wichtige Frage")]
        try await persistence.persist([conversation])
        let good = try Data(contentsOf: paths.conversations)
        let damaged = String(decoding: good, as: UTF8.self)
            .replacingOccurrences(of: "\"text\":\"Wichtige Frage\"", with: "\"text\":12345")
        XCTAssertTrue(damaged.contains("\"text\":12345"))
        try damaged.data(using: .utf8)?.write(to: paths.conversations)

        let store = ChatStore(media: MediaStore(paths: paths), paths: paths)
        XCTAssertEqual(store.conversations.first?.messages.first?.text, "", "geborgen wird, was lesbar blieb")
        let problem = try XCTUnwrap(store.storageProblem,
                                    "eine teilweise unlesbare Historie darf nicht unbemerkt bleiben")
        XCTAssertTrue(problem.contains("conversations.json.unlesbar-"), problem)
        XCTAssertNotEqual(problem, L.t("storage_load_failed"))
    }

    func testLaunchReclaimsStrandedTrashFiles() throws {
        let paths = StoragePaths(documents: tempDocuments())
        try FileManager.default.createDirectory(at: paths.trash, withIntermediateDirectories: true)
        let stranded = paths.trash.appendingPathComponent("9F2C_img_stranded.jpg")
        try Data([7, 7]).write(to: stranded)
        let store = ChatStore(media: MediaStore(paths: paths), paths: paths)
        XCTAssertEqual(store.conversations.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stranded.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: paths.trash.path).isEmpty)
    }

    func testNewConversationIsPrependedAndBecomesCurrent() {
        let (store, _) = makeSandbox()
        let previous = store.currentID
        store.newConversation()
        XCTAssertEqual(store.conversations.count, 2)
        XCTAssertNotEqual(store.currentID, previous)
        XCTAssertEqual(store.current?.messages.count, 0)
    }

    func testAFreshStartKeepsAnAlreadyEmptyChat() {
        let (store, _) = makeSandbox()
        let empty = store.currentID
        store.startFreshConversation()
        XCTAssertEqual(store.conversations.count, 1, "leere Chats werden nicht gestapelt")
        XCTAssertEqual(store.currentID, empty)
    }

    func testAFreshStartOpensANewChatWhenTheCurrentOneHasMessages() throws {
        let (store, _) = makeSandbox()
        let used = try XCTUnwrap(store.current?.id)
        store.appendMessage(ChatMessage(role: .user, text: "Wie spät ist es"), to: used)
        store.startFreshConversation()
        XCTAssertEqual(store.conversations.count, 2)
        XCTAssertNotEqual(store.currentID, used)
        XCTAssertEqual(store.current?.messages.count, 0)
        XCTAssertEqual(store.conversations.last?.id, used, "der alte Chat bleibt im Verlauf")
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

    func testSwitchingTheConversationKeepsOnlyItsOwnRenditionsInMemory() async throws {
        let (store, _) = makeSandbox()
        let first = try XCTUnwrap(store.currentID)
        let firstFile = try XCTUnwrap(store.media.store(FakePicture.make()))
        store.appendMessage(ChatMessage(role: .user, text: "Bild", images: [Attachment(file: firstFile)]), to: first)
        store.newConversation()
        let second = try XCTUnwrap(store.currentID)
        let secondFile = try XCTUnwrap(store.media.store(FakePicture.make()))
        store.appendMessage(ChatMessage(role: .user, text: "Bild", images: [Attachment(file: secondFile)]), to: second)
        store.images.load(firstFile)
        store.images.load(secondFile)
        await waitUntil { store.images.rendition(for: firstFile) != nil && store.images.rendition(for: secondFile) != nil }
        store.currentID = first
        XCTAssertNotNil(store.images.rendition(for: firstFile))
        XCTAssertNil(store.images.rendition(for: secondFile), "Bilder fremder Unterhaltungen bleiben nicht im Speicher")
    }

    func testRemovingCurrentConversationSelectsAnotherOne() throws {
        let (store, _) = makeSandbox()
        let first = try XCTUnwrap(store.currentID)
        store.newConversation()
        let second = try XCTUnwrap(store.currentID)
        _ = store.removeConversation(second)
        XCTAssertEqual(store.currentID, first)
    }

    func testRemovingTheLastConversationCreatesAFreshOne() throws {
        let (store, _) = makeSandbox()
        _ = store.removeConversation(try XCTUnwrap(store.currentID))
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

    func testFlushPendingSaveWritesBeforeTheDebounceElapses() async throws {
        let (store, paths) = makeSandbox()
        let id = try XCTUnwrap(store.current?.id)
        store.appendMessage(ChatMessage(role: .user, text: "Frage"), to: id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.conversationsFolder.path))
        await store.flushPendingSave()
        let reloaded = try storedConversations(at: paths)
        XCTAssertEqual(reloaded.first?.messages.count, 1)
    }

    func testAStoreThatCouldNotReadItsHistoryReportsItAndKeepsTheBytes() async throws {
        let paths = StoragePaths(documents: tempDocuments())
        try FileManager.default.createDirectory(at: paths.support, withIntermediateDirectories: true)
        let bytes = Data("{ kein json ".utf8)
        try bytes.write(to: paths.conversations)
        let (store, _) = makeSandbox(at: paths)

        XCTAssertEqual(store.conversations.count, 1, "der Chat beginnt leer statt zu verschwinden")
        XCTAssertEqual(store.storageProblem, L.t("storage_load_failed"))

        await store.flushPendingSave()
        XCTAssertEqual(store.storageProblem, L.t("storage_load_failed"),
                       "ein gelungenen Neuanfang-Fehler darf die Lesewarnung nicht stillschweigen")

        let quarantined = try XCTUnwrap(FileManager.default.contentsOfDirectory(atPath: paths.support.path)
            .first { $0.hasPrefix("conversations.json.corrupt-") })
        XCTAssertEqual(try Data(contentsOf: paths.support.appendingPathComponent(quarantined)), bytes)
    }

    func testAcknowledgingTheLoadProblemLetsLaterSuccessesClearTheBar() async throws {
        let paths = StoragePaths(documents: tempDocuments())
        try FileManager.default.createDirectory(at: paths.support, withIntermediateDirectories: true)
        try Data("{ kein json ".utf8).write(to: paths.conversations)
        let (store, _) = makeSandbox(at: paths)
        store.dismissStorageProblem()
        await store.flushPendingSave()
        XCTAssertNil(store.storageProblem)
    }

    func testAnOfferRowIsStoredWithItsOwnHeading() async throws {
        let (store, paths) = makeSandbox()
        let id = try XCTUnwrap(store.current?.id)
        store.appendAssistant("Angebote\n- **idealo** 612,00 €", model: "qwen3.8-flash", elapsed: 1, to: id,
                              sources: [Fixtures.source("Idealo", "https://idealo.de/a", "idealo.de")],
                              sourcesHeadingKey: "price_head")
        await store.flushPendingSave()
        let reloaded = try storedConversations(at: paths)
        let message = try XCTUnwrap(reloaded.first?.messages.last)
        XCTAssertEqual(message.sourcesHeadingKey, "price_head")
        XCTAssertEqual(message.sources?.map(\.domain), ["idealo.de"])
    }

    func testAnOlderResearchAnswerWithoutTheSourceHeadingStillDecodes() throws {
        let message = ChatMessage(role: .assistant, text: "Quellen",
                                  sources: [Fixtures.source("Statista", "https://a.test", "a.test")],
                                  sourcesHeadingKey: "price_head")
        let encoded = try JSONEncoder().encode([message])
        var stored = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        stored[0].removeValue(forKey: "sourcesHeadingKey")
        let legacy = try JSONSerialization.data(withJSONObject: stored)
        let decoded = try JSONDecoder().decode([ChatMessage].self, from: legacy)
        XCTAssertNil(decoded.first?.sourcesHeadingKey)
        XCTAssertEqual(decoded.first?.sources?.map(\.domain), ["a.test"])
    }

    func testARouteAnswerRemembersItsOwnHeading() async throws {
        let (store, paths) = makeSandbox()
        let id = try XCTUnwrap(store.current?.id)
        let place = NearbyPlace(name: "Torstraße 1", latitude: 52.52, longitude: 13.405,
                                metres: nil, mode: .driving)
        store.appendAssistant("Route\n- Torstraße 1", model: "qwen3.8-flash", elapsed: 1, to: id,
                              placeGroups: [PlaceGroup(headingKey: "route_head", places: [place])])
        await store.flushPendingSave()
        let reloaded = try storedConversations(at: paths)
        let message = try XCTUnwrap(reloaded.first?.messages.last)
        XCTAssertEqual(message.placeGroups?.map(\.headingKey), ["route_head"])
        XCTAssertEqual(message.allPlaces.map(\.name), ["Torstraße 1"])
    }

    private func legacyAnswer(_ fields: [String: Any]) throws -> ChatMessage? {
        var stored: [String: Any] = ["id": "6E2A1C4D-5B7F-4A10-9C8D-0E1F2A3B4C5D", "role": "assistant",
                                     "text": "In deiner Nähe", "images": [], "date": 800_000_000]
        stored.merge(fields) { $1 }
        let data = try JSONSerialization.data(withJSONObject: [stored])
        return try JSONDecoder().decode([ChatMessage].self, from: data).first
    }

    func testAnOlderAnswerWithoutTheHeadingKeyStillDecodes() throws {
        let place: [String: Any] = ["name": "REWE", "latitude": 52.52, "longitude": 13.405, "metres": 400]
        let message = try XCTUnwrap(legacyAnswer(["places": [place]]))
        XCTAssertEqual(message.placeGroups?.map(\.headingKey), [PlaceGroup.defaultHeadingKey])
        XCTAssertEqual(message.allPlaces.map(\.name), ["REWE"])
    }

    func testAnOlderRouteAnswerKeepsItsHeading() throws {
        let place: [String: Any] = ["name": "Torstraße 1", "latitude": 52.52, "longitude": 13.405]
        let message = try XCTUnwrap(legacyAnswer(["places": [place], "placesHeadingKey": "route_head"]))
        XCTAssertEqual(message.placeGroups?.map(\.headingKey), ["route_head"])
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

extension ChatStoreTests {
    func testATitleNeverCarriesALineBreak() {
        XCTAssertEqual(ChatStore.title(of: "Erste Frage mit ganz vielen Zeichen\n\nzweite Zeile"),
                       "Erste Frage mit ganz vielen Zeichen")
        XCTAssertEqual(ChatStore.title(of: "   \n  Zweiter Anfang"), "Zweiter Anfang")
        XCTAssertEqual(ChatStore.title(of: String(repeating: "x", count: 60)).count, 40)
    }
}
