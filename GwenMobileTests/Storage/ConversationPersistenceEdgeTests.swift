@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class ConversationPersistenceEdgeTests: XCTestCase {
    private let manager = FileManager.default

    private func fixture(_ text: String) -> [Conversation] {
        var conversation = Conversation(title: "Zahnarzt")
        conversation.messages = [ChatMessage(role: .user, text: text)]
        return [conversation]
    }

    private func bytes(_ conversations: [Conversation]) throws -> Data {
        try JSONEncoder().encode(conversations)
    }

    func testAFailedLegacyPreparationDoesNotTouchTheOldFile() throws {
        let parent = tempDocuments()
        let blocker = parent.appendingPathComponent("blocker")
        try Data([0]).write(to: blocker)
        let url = blocker.appendingPathComponent("conversations.json")
        let legacy = tempDocuments().appendingPathComponent("conversations.json")
        try bytes(fixture("alt")).write(to: legacy)
        let persistence = ConversationFilePersistence(url: url, legacyURL: legacy)
        guard case .loaded(let loaded) = persistence.load() else {
            return XCTFail("die alte Datei muss als Rückfall gelesen werden")
        }
        XCTAssertEqual(loaded.first?.messages.first?.text, "alt")
        XCTAssertTrue(manager.fileExists(atPath: legacy.path))
    }

    func testAFailedLegacyMoveKeepsTheOldFile() throws {
        let parent = tempDocuments()
        let folder = parent.appendingPathComponent("unterordner")
        let url = folder.appendingPathComponent("conversations.json")
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let legacy = tempDocuments().appendingPathComponent("conversations.json")
        try bytes(fixture("alt")).write(to: legacy)
        try manager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.path)
        defer { try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path) }
        let persistence = ConversationFilePersistence(url: url, legacyURL: legacy)
        guard case .loaded(let loaded) = persistence.load() else {
            return XCTFail("die alte Datei muss als Rückfall gelesen werden")
        }
        XCTAssertEqual(loaded.first?.messages.first?.text, "alt")
        XCTAssertTrue(manager.fileExists(atPath: legacy.path))
    }

    func testAFailedRescueKeepsTheOriginalAsPreservedFile() throws {
        let directory = tempDocuments()
        let url = directory.appendingPathComponent("conversations.json")
        try Data("{kaputt".utf8).write(to: url)
        try bytes(fixture("sicherung")).write(to: url.appendingPathExtension("bak"))
        try manager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        let persistence = ConversationFilePersistence(url: url)
        guard case .recovered(let loaded, let preserved) = persistence.load() else {
            return XCTFail("Sicherungskopie wurde nicht gelesen")
        }
        XCTAssertEqual(loaded.first?.messages.first?.text, "sicherung")
        XCTAssertEqual(preserved.path, url.path)
    }

    func testAfterNinetyNineStampedCopiesTheNameGetsAUuid() throws {
        let directory = tempDocuments()
        let url = directory.appendingPathComponent("conversations.json")
        try Data("{kaputt".utf8).write(to: url)
        try bytes(fixture("sicherung")).write(to: url.appendingPathExtension("bak"))
        let stamp = "2026-10-08-120000"
        try bytes(fixture("x")).write(to: url.appendingPathExtension("corrupt-\(stamp)"))
        for index in 2...99 {
            try bytes(fixture("x")).write(to: url.appendingPathExtension("corrupt-\(stamp)-\(index)"))
        }
        let persistence = ConversationFilePersistence(url: url, stamp: { stamp })
        guard case .recovered(_, let preserved) = persistence.load() else {
            return XCTFail("Sicherungskopie wurde nicht gelesen")
        }
        XCTAssertTrue(preserved.lastPathComponent.contains("corrupt-\(stamp)-"), preserved.lastPathComponent)
        XCTAssertNotEqual(preserved, url.appendingPathExtension("corrupt-\(stamp)-99"))
    }

    func testAFailedBackupCopyStillReportsTheWriteAsFailed() async throws {
        let directory = tempDocuments()
        let url = directory.appendingPathComponent("conversations.json")
        try bytes(fixture("alt")).write(to: url)
        try manager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        let persistence = ConversationFilePersistence(url: url)
        do {
            try await persistence.persist(fixture("neu"))
            XCTFail("Schreiben in ein gesperrtes Verzeichnis darf nicht gelingen")
        } catch {
        }
    }
}
