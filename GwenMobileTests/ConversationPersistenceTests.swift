import XCTest
@testable import GwenMobile

final class ConversationPersistenceTests: XCTestCase {
    private func url(in dir: URL) -> URL { dir.appendingPathComponent("conversations.json") }

    private func fixture(_ text: String) -> [Conversation] {
        var conversation = Conversation(title: "Zahnarzt")
        conversation.messages = [ChatMessage(role: .user, text: text)]
        return [conversation]
    }

    func testMissingFileLoadsNothing() throws {
        let persistence = ConversationFilePersistence(url: url(in: tempDocuments()))
        XCTAssertNil(persistence.load())
    }

    func testPersistNowStoresEveryConversationAndReadsItBack() throws {
        let persistence = ConversationFilePersistence(url: url(in: tempDocuments()))
        try persistence.persistNow(fixture("Frage"))
        let loaded = try XCTUnwrap(persistence.load())
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.title, "Zahnarzt")
        XCTAssertEqual(loaded.first?.messages.first?.text, "Frage")
    }

    func testAsyncWriteCarriesTheSamePayloadAsTheImmediateOne() async throws {
        let asyncPersistence = ConversationFilePersistence(url: url(in: tempDocuments()))
        try await asyncPersistence.persist(fixture("Spaeter"))
        let immediatePersistence = ConversationFilePersistence(url: url(in: tempDocuments()))
        try immediatePersistence.persistNow(fixture("Spaeter"))
        let written = try XCTUnwrap(asyncPersistence.load())
        let reference = try XCTUnwrap(immediatePersistence.load())
        XCTAssertEqual(written.count, reference.count)
        XCTAssertEqual(written.first?.title, reference.first?.title)
        XCTAssertEqual(written.first?.messages.first?.text, reference.first?.messages.first?.text)
    }

    func testUnusableTargetPathFailsBothWays() throws {
        let dir = tempDocuments()
        try FileManager.default.createDirectory(at: url(in: dir), withIntermediateDirectories: true)
        let persistence = ConversationFilePersistence(url: url(in: dir))
        XCTAssertThrowsError(try persistence.persistNow(fixture("Frage")))
        XCTAssertNil(persistence.load())
    }
}
