@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

private final class ScriptedFileManager: FileManager {
    var moveFailure: ((URL, URL) -> Error?)?
    var removeFailure: ((URL) -> Error?)?
    var createsDestinationOnMoveFailure = false

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if let error = moveFailure?(srcURL, dstURL) {
            if createsDestinationOnMoveFailure {
                try? super.createDirectory(at: dstURL, withIntermediateDirectories: true)
            }
            throw error
        }
        try super.moveItem(at: srcURL, to: dstURL)
    }

    override func removeItem(at url: URL) throws {
        if let error = removeFailure?(url) { throw error }
        try super.removeItem(at: url)
    }
}

final class ConversationFolderPersistenceTests: XCTestCase {
    private let manager = FileManager.default

    private func store(in root: URL, onWrite: (@Sendable (UUID) -> Void)? = nil) -> ConversationFolderPersistence {
        ConversationFolderPersistence(
            folder: root.appendingPathComponent("conversations", isDirectory: true),
            legacy: ConversationFilePersistence(url: root.appendingPathComponent("conversations.json")),
            onWrite: onWrite)
    }

    private func legacy(in root: URL) -> ConversationFilePersistence {
        ConversationFilePersistence(url: root.appendingPathComponent("conversations.json"))
    }

    private func fixture(_ text: String, id: UUID = UUID()) -> Conversation {
        var conversation = Conversation(id: id, title: "Zahnarzt",
                                        messages: [ChatMessage(role: .user, text: text)])
        conversation.updatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        return conversation
    }

    private func texts(_ load: ConversationLoad) -> [String] {
        (load.conversations ?? []).map { $0.messages.first?.text ?? "" }
    }

    private func fileURL(_ root: URL, _ id: UUID) -> URL {
        root.appendingPathComponent("conversations", isDirectory: true)
            .appendingPathComponent(ConversationFolderPersistence.fileName(id))
    }

    private func fileNames(_ root: URL) -> [String] {
        (try? manager.contentsOfDirectory(atPath: root.appendingPathComponent("conversations").path)) ?? []
    }

    func testAFailedBackupRemovalDoesNotStopThePersist() async throws {
        let root = tempDocuments()
        let persistence = store(in: root)
        let gone = fixture("Geht")
        try await persistence.persist([gone])
        var changed = gone
        changed.messages.append(ChatMessage(role: .assistant, text: "Antwort"))
        try await persistence.persist([changed])
        let backup = fileURL(root, gone.id).appendingPathExtension("bak")
        XCTAssertTrue(manager.fileExists(atPath: backup.path))
        let scripted = ScriptedFileManager()
        scripted.removeFailure = { url in
            url.lastPathComponent.hasSuffix(".bak") ? APIError(message: "kaputt") : nil
        }
        let original = ConversationFolderPersistence.manager
        ConversationFolderPersistence.manager = scripted
        defer { ConversationFolderPersistence.manager = original }
        try await store(in: root).persist([fixture("Bleibt")])
        XCTAssertFalse(manager.fileExists(atPath: fileURL(root, gone.id).path))
        XCTAssertTrue(manager.fileExists(atPath: backup.path))
    }

    func testAFailedFolderMoveRestoresTheOldFolder() async throws {
        let root = tempDocuments()
        try await legacy(in: root).persist([fixture("Alt")])
        let folder = root.appendingPathComponent("conversations", isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let scripted = ScriptedFileManager()
        scripted.moveFailure = { source, destination in
            source.lastPathComponent.hasPrefix("conversations.import-") && destination == folder
                ? APIError(message: "kaputt") : nil
        }
        let original = ConversationFolderPersistence.manager
        ConversationFolderPersistence.manager = scripted
        defer { ConversationFolderPersistence.manager = original }
        XCTAssertEqual(texts(store(in: root).load()), ["Alt"])
        XCTAssertTrue(manager.fileExists(atPath: folder.path))
    }

    func testAFailedRestoreLeavesTheLegacySnapshot() async throws {
        let root = tempDocuments()
        try await legacy(in: root).persist([fixture("Alt")])
        let folder = root.appendingPathComponent("conversations", isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let scripted = ScriptedFileManager()
        scripted.moveFailure = { source, destination in
            destination == folder && (source.lastPathComponent.hasPrefix("conversations.import-")
                || source.lastPathComponent.hasPrefix("conversations.old-"))
                ? APIError(message: "kaputt") : nil
        }
        let original = ConversationFolderPersistence.manager
        ConversationFolderPersistence.manager = scripted
        defer { ConversationFolderPersistence.manager = original }
        XCTAssertEqual(texts(store(in: root).load()), ["Alt"])
        XCTAssertFalse(manager.fileExists(atPath: folder.path))
    }

    func testAFailedOldFolderCleanupKeepsTheNewFolder() async throws {
        let root = tempDocuments()
        try await legacy(in: root).persist([fixture("Alt")])
        let folder = root.appendingPathComponent("conversations", isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let scripted = ScriptedFileManager()
        scripted.removeFailure = { url in
            url.lastPathComponent.hasPrefix("conversations.old-") ? APIError(message: "kaputt") : nil
        }
        let original = ConversationFolderPersistence.manager
        ConversationFolderPersistence.manager = scripted
        defer { ConversationFolderPersistence.manager = original }
        XCTAssertEqual(texts(store(in: root).load()), ["Alt"])
        XCTAssertTrue(manager.fileExists(atPath: folder.path))
        XCTAssertEqual(store(in: root).load().conversations?.count, 1)
    }

    func testPersistWritesOnlyChangedFiles() async throws {
        let root = tempDocuments()
        let written = LockedValue([UUID]())
        let persistence = store(in: root, onWrite: { id in written.mutate { $0.append(id) } })
        let first = fixture("Erste")
        let second = fixture("Zweite")

        try await persistence.persist([first, second])
        XCTAssertEqual(Set(written.current), [first.id, second.id], "beide Chats werden einmal geschrieben")
        try await persistence.persist([first, second])
        XCTAssertEqual(written.current.count, 2, "unveränderte Chats werden nicht erneut geschrieben")

        var changed = second
        changed.messages.append(ChatMessage(role: .assistant, text: "Antwort"))
        try await persistence.persist([first, changed])
        XCTAssertEqual(written.current.count, 3, "nur der geänderte Chat wird geschrieben")
        XCTAssertEqual(Set(written.current.suffix(1)), [second.id])
        XCTAssertTrue(manager.fileExists(atPath: fileURL(root, second.id).appendingPathExtension("bak").path))
        XCTAssertFalse(manager.fileExists(atPath: fileURL(root, first.id).appendingPathExtension("bak").path))
    }

    func testRemovedConversationsLoseTheirFileAndBackup() async throws {
        let root = tempDocuments()
        let persistence = store(in: root)
        let kept = fixture("Bleibt")
        let gone = fixture("Geht")
        try await persistence.persist([kept, gone])
        var changed = gone
        changed.messages.append(ChatMessage(role: .assistant, text: "Antwort"))
        try await persistence.persist([kept, changed])
        XCTAssertTrue(manager.fileExists(atPath: fileURL(root, gone.id).appendingPathExtension("bak").path))

        try await persistence.persist([kept])
        XCTAssertFalse(manager.fileExists(atPath: fileURL(root, gone.id).path))
        XCTAssertFalse(manager.fileExists(atPath: fileURL(root, gone.id).appendingPathExtension("bak").path))
        XCTAssertEqual(texts(persistence.load()), ["Bleibt"])
    }

    func testFreshInstanceLoadsTheStoredFiles() async throws {
        let root = tempDocuments()
        try await store(in: root).persist([fixture("Erste"), fixture("Zweite")])
        let fresh = store(in: root)
        XCTAssertEqual(Set(texts(fresh.load())), ["Erste", "Zweite"])
    }

    func testMarkerAloneIsAnInitializedEmptyStore() throws {
        let root = tempDocuments()
        try manager.createDirectory(at: root.appendingPathComponent("conversations"),
                                    withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("conversations/imported"))
        try JSONEncoder().encode([fixture("Alte Datei")]).write(to: root.appendingPathComponent("conversations.json"))
        XCTAssertEqual(store(in: root).load(), .nothing, "eine leere Ablage importiert die alte Datei nicht erneut")
    }

    func testPersistWithoutConversationsDoesNotResurrectTheLegacySnapshot() async throws {
        let root = tempDocuments()
        try await legacy(in: root).persist([fixture("Alt")])
        let persistence = store(in: root)
        XCTAssertEqual(texts(persistence.load()), ["Alt"])
        try await persistence.persist([])
        XCTAssertEqual(store(in: root).load(), .nothing)
        XCTAssertTrue(manager.fileExists(atPath: root.appendingPathComponent("conversations.json").path),
                      "die alte Sicherung bleibt für einen Rückschritt liegen")
    }

    func testDamagedFieldsAreRecoveredWithACopy() async throws {
        let root = tempDocuments()
        let persistence = store(in: root)
        let conversation = fixture("Wichtige Frage")
        try await persistence.persist([conversation])
        let url = fileURL(root, conversation.id)
        let good = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        let damaged = good.replacingOccurrences(of: "\"text\":\"Wichtige Frage\"", with: "\"text\":12345")
        XCTAssertTrue(damaged.contains("\"text\":12345"))
        try damaged.data(using: .utf8)?.write(to: url)

        guard case .recovered(let loaded, let preserved) = persistence.load() else {
            return XCTFail("ein Feld mit falschem Typ muss als Rettung gemeldet werden")
        }
        XCTAssertEqual(loaded.first?.messages.first?.text, "")
        XCTAssertTrue(manager.fileExists(atPath: preserved.path))
        XCTAssertTrue(manager.fileExists(atPath: url.path), "die lebende Datei bleibt bis zum nächsten Speichern")
    }

    func testUnreadableFileFallsBackToItsBackup() async throws {
        let root = tempDocuments()
        let persistence = store(in: root)
        let id = UUID()
        try await persistence.persist([fixture("Erste", id: id)])
        var changed = fixture("Zweite", id: id)
        changed.messages.append(ChatMessage(role: .assistant, text: "Antwort"))
        try await persistence.persist([changed])
        let url = fileURL(root, id)
        try Data("{ kaputt".utf8).write(to: url)

        guard case .recovered(let loaded, let preserved) = store(in: root).load() else {
            return XCTFail("die Sicherungskopie muss einspringen")
        }
        XCTAssertEqual(loaded.first?.messages.first?.text, "Erste")
        XCTAssertTrue(manager.fileExists(atPath: preserved.path))
        XCTAssertFalse(manager.fileExists(atPath: url.path), "die unlesbare Datei wird weggeräumt")
    }

    func testOneUnreadableFileDoesNotHideTheOthers() async throws {
        let root = tempDocuments()
        let persistence = store(in: root)
        let kept = fixture("Bleibt")
        try await persistence.persist([kept])
        let broken = fileURL(root, UUID())
        try Data("{ kaputt".utf8).write(to: broken)

        guard case .recovered(let loaded, let preserved) = persistence.load() else {
            return XCTFail("eine kaputte Datei darf die lesbaren nicht mitnehmen")
        }
        XCTAssertEqual(loaded.map { $0.messages.first?.text }, ["Bleibt"])
        XCTAssertTrue(manager.fileExists(atPath: preserved.path))
        XCTAssertFalse(manager.fileExists(atPath: broken.path))
    }

    func testUnreadableFileWithoutBackupIsQuarantined() throws {
        let root = tempDocuments()
        try manager.createDirectory(at: root.appendingPathComponent("conversations"),
                                    withIntermediateDirectories: true)
        let broken = fileURL(root, UUID())
        try Data("{ kaputt".utf8).write(to: broken)

        guard case .quarantined(let preserved) = store(in: root).load() else {
            return XCTFail("ohne Sicherung bleibt nur die Quarantäne")
        }
        XCTAssertTrue(manager.fileExists(atPath: preserved.path))
        XCTAssertFalse(manager.fileExists(atPath: broken.path))
    }

    func testLegacySnapshotIsMigratedAndNotRewritten() async throws {
        let root = tempDocuments()
        try await legacy(in: root).persist([fixture("Erste"), fixture("Zweite")])
        let written = LockedValue([UUID]())
        let persistence = store(in: root, onWrite: { id in written.mutate { $0.append(id) } })

        XCTAssertEqual(Set(texts(persistence.load())), ["Erste", "Zweite"])
        XCTAssertTrue(manager.fileExists(atPath: root.appendingPathComponent("conversations/imported").path))
        XCTAssertTrue(manager.fileExists(atPath: root.appendingPathComponent("conversations.json").path))

        let loaded = persistence.load().conversations ?? []
        try await persistence.persist(loaded)
        XCTAssertTrue(written.current.isEmpty, "der Import hat die Dateien schon geschrieben")
    }

    func testAnEmptyLegacySnapshotInitializesTheFolder() async throws {
        let root = tempDocuments()
        try await legacy(in: root).persist([])
        let persistence = store(in: root)
        XCTAssertEqual(persistence.load(), .loaded([]))
        XCTAssertTrue(manager.fileExists(atPath: root.appendingPathComponent("conversations/imported").path))
    }

    func testRecoveredLegacySnapshotKeepsItsWarning() async throws {
        let root = tempDocuments()
        let file = root.appendingPathComponent("conversations.json")
        try await legacy(in: root).persist([fixture("Wichtige Frage")])
        let good = String(decoding: try Data(contentsOf: file), as: UTF8.self)
        try good.replacingOccurrences(of: "\"text\":\"Wichtige Frage\"", with: "\"text\":12345")
            .data(using: .utf8)?.write(to: file)

        let persistence = store(in: root)
        guard case .recovered(let loaded, let preserved) = persistence.load() else {
            return XCTFail("die Rettungswarnung der alten Ablage muss weiterreichen")
        }
        XCTAssertEqual(loaded.first?.messages.first?.text, "")
        XCTAssertTrue(preserved.lastPathComponent.hasPrefix("conversations.json.unlesbar-"),
                      preserved.lastPathComponent)
    }

    func testQuarantinedLegacySnapshotIsPassedThrough() throws {
        let root = tempDocuments()
        try Data("{ kein json".utf8).write(to: root.appendingPathComponent("conversations.json"))
        guard case .quarantined(let preserved) = store(in: root).load() else {
            return XCTFail("eine unlesbare alte Ablage wandert in Quarantäne")
        }
        XCTAssertTrue(preserved.lastPathComponent.hasPrefix("conversations.json.corrupt-"),
                      preserved.lastPathComponent)
        XCTAssertFalse(manager.fileExists(atPath: root.appendingPathComponent("conversations").path))
    }

    func testFailedMigrationKeepsTheLegacySnapshot() async throws {
        let root = tempDocuments()
        try await legacy(in: root).persist([fixture("Alt")])
        try manager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
        defer { try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path) }

        let persistence = store(in: root)
        XCTAssertEqual(texts(persistence.load()), ["Alt"], "der Import scheitert, die Daten bleiben")
        XCTAssertTrue(manager.fileExists(atPath: root.appendingPathComponent("conversations.json").path))
        XCTAssertFalse(manager.fileExists(atPath: root.appendingPathComponent("conversations").path))
    }

    func testLeftoverStagingFoldersAreRemoved() async throws {
        let root = tempDocuments()
        try await legacy(in: root).persist([fixture("Alt")])
        let leftover = root.appendingPathComponent("conversations.import-deadbeef")
        try manager.createDirectory(at: leftover, withIntermediateDirectories: true)
        try Data([1]).write(to: leftover.appendingPathComponent("halb.json"))

        XCTAssertEqual(texts(store(in: root).load()), ["Alt"])
        XCTAssertFalse(manager.fileExists(atPath: leftover.path))
        XCTAssertTrue(manager.fileExists(atPath: root.appendingPathComponent("conversations/imported").path))
    }

    func testPersistFailsWhenTheFolderIsBlockedByAFile() async throws {
        let root = tempDocuments()
        try Data([0]).write(to: root.appendingPathComponent("conversations"))
        do {
            try await store(in: root).persist([fixture("Neu")])
            XCTFail("ein blockierter Ordner darf nicht still gelingen")
        } catch {
        }
    }

    func testAFolderBlockedByAFileFallsBackToTheLegacySnapshot() async throws {
        let root = tempDocuments()
        try await legacy(in: root).persist([fixture("Alt")])
        try Data([0]).write(to: root.appendingPathComponent("conversations"))
        XCTAssertEqual(texts(store(in: root).load()), ["Alt"])
    }

    func testStoredFilesCarryTheirConversationID() async throws {
        let root = tempDocuments()
        let id = UUID()
        try await store(in: root).persist([fixture("Erste", id: id)])
        XCTAssertEqual(fileNames(root).filter { $0.hasSuffix(".json") },
                       [ConversationFolderPersistence.fileName(id)])
        XCTAssertEqual(ConversationFolderPersistence.fileName(id), id.uuidString + ".json")
    }
}
