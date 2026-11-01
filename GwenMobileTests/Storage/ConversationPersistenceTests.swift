@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class ConversationPersistenceTests: XCTestCase {
    private let manager = FileManager.default

    private func url(in dir: URL) -> URL { dir.appendingPathComponent("conversations.json") }

    private func fixture(_ text: String) -> [Conversation] {
        var conversation = Conversation(title: "Zahnarzt")
        conversation.messages = [ChatMessage(role: .user, text: text)]
        return [conversation]
    }

    func testMissingFileLoadsNothing() throws {
        let persistence = ConversationFilePersistence(url: url(in: tempDocuments()))
        XCTAssertEqual(persistence.load(), .nothing)
    }

    func testPersistStoresEveryConversationAndReadsItBack() async throws {
        let persistence = ConversationFilePersistence(url: url(in: tempDocuments()))
        try await persistence.persist(fixture("Frage"))
        let loaded = try XCTUnwrap(persistence.load().conversations)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.title, "Zahnarzt")
        XCTAssertEqual(loaded.first?.messages.first?.text, "Frage")
    }

    func testEveryWriteLeavesThePreviousSnapshotAsABackupCopy() async throws {
        let persistence = ConversationFilePersistence(url: url(in: tempDocuments()))
        try await persistence.persist(fixture("Erste"))
        try await persistence.persist(fixture("Zweite"))
        XCTAssertTrue(manager.fileExists(atPath: persistence.backup.path))
        let backupData = try Data(contentsOf: persistence.backup)
        let backup = try JSONDecoder().decode([Conversation].self, from: backupData)
        XCTAssertEqual(backup.first?.messages.first?.text, "Erste")
        XCTAssertEqual(persistence.load().conversations?.first?.messages.first?.text, "Zweite")
    }

    func testAnUnreadableFileFallsBackToTheBackupCopy() async throws {
        let persistence = ConversationFilePersistence(url: url(in: tempDocuments()))
        try await persistence.persist(fixture("Von der Sicherungskopie"))
        try await persistence.persist(fixture("Gleich wird das original kaputt"))
        let backupData = try Data(contentsOf: persistence.backup)
        try Data("{" .utf8).write(to: persistence.url)

        guard case .recovered(let loaded, let preserved) = persistence.load() else {
            return XCTFail("eine gerettete Historie muss als Rettung gemeldet werden")
        }
        XCTAssertEqual(loaded.first?.messages.first?.text, "Von der Sicherungskopie")
        XCTAssertTrue(manager.fileExists(atPath: preserved.path), "das unlesbare Original bleibt erhalten")
        XCTAssertEqual(try Data(contentsOf: preserved), Data("{".utf8),
                       "das unlesbare Original liegt in der Quarantäne")
        XCTAssertEqual(try Data(contentsOf: persistence.url), backupData,
                       "die lebende Datei trägt wieder den letzten guten Stand")

        guard case .loaded(let again) = persistence.load() else {
            return XCTFail("der nächste Start darf nicht erneut quarantänisieren")
        }
        XCTAssertEqual(again.first?.messages.first?.text, "Von der Sicherungskopie")
    }

    func testAFieldOfTheWrongTypeIsReportedInsteadOfQuietlyEmptied() async throws {
        let persistence = ConversationFilePersistence(url: url(in: tempDocuments()))
        try await persistence.persist(fixture("Wichtige Frage"))
        let good = String(decoding: try Data(contentsOf: persistence.url), as: UTF8.self)
        let damaged = good.replacingOccurrences(of: "\"text\":\"Wichtige Frage\"", with: "\"text\":12345")
        XCTAssertTrue(damaged.contains("\"text\":12345"), "die Probe muss das Feld wirklich verletzen")
        let damagedBytes = try XCTUnwrap(damaged.data(using: .utf8))
        try damagedBytes.write(to: persistence.url)

        guard case .recovered(let stored, let preserved) = persistence.load() else {
            return XCTFail("ein Feld mit falschem Typ darf nicht als intakte Historie durchgehen")
        }
        XCTAssertEqual(stored.first?.messages.first?.text, "", "gerettet wird, was lesbar blieb")
        XCTAssertTrue(manager.fileExists(atPath: preserved.path))
        XCTAssertEqual(try Data(contentsOf: preserved), damagedBytes,
                       "die Kopie hält die unlesbare Fassung fest")
        XCTAssertTrue(manager.fileExists(atPath: persistence.url.path),
                      "die lebende Datei bleibt liegen, bis der nächste Speichern sie ersetzt")
    }

    func testEveryDamagedLoadKeepsItsOwnCopy() async throws {
        let persistence = ConversationFilePersistence(url: url(in: tempDocuments()))
        try await persistence.persist(fixture("Wichtige Frage"))
        let clean = String(decoding: try Data(contentsOf: persistence.url), as: UTF8.self)

        func damage(_ value: Int) throws -> URL? {
            let broken = clean.replacingOccurrences(of: "\"text\":\"Wichtige Frage\"",
                                                    with: "\"text\":\(value)")
            try broken.data(using: .utf8)?.write(to: persistence.url)
            guard case .recovered(_, let preserved) = persistence.load() else {
                XCTFail("eine Typedateu muss als Rettung melden")
                return nil
            }
            return preserved
        }

        let first = try XCTUnwrap(damage(1))
        let second = try XCTUnwrap(damage(2))
        XCTAssertNotEqual(first.path, second.path, "zwei Rettungen derselben Sekunde verlieren keine Kopie")
        XCTAssertTrue(manager.fileExists(atPath: first.path))
        XCTAssertTrue(manager.fileExists(atPath: second.path))
    }

    func testAnUnreadableFileWithoutABackupIsMovedAsideInsteadOfReportedEmpty() throws {
        let dir = tempDocuments()
        let persistence = ConversationFilePersistence(url: url(in: dir))
        let bytes = Data("{ kein json, nur text".utf8)
        try bytes.write(to: persistence.url)

        let moved = try XCTUnwrap(caseURL(persistence.load()))
        XCTAssertTrue(manager.fileExists(atPath: moved.path))
        XCTAssertEqual(try Data(contentsOf: moved), bytes)
        XCTAssertFalse(manager.fileExists(atPath: persistence.url.path),
                       "the live path has to be free for the fresh history")
    }

    func testAHistoryThatIsMerelySloppyIsLoadedInsteadOfQuarantined() throws {
        let persistence = ConversationFilePersistence(url: url(in: tempDocuments()))
        let bytes = Data(#"[{"messages":[{"role":"user"}]}]"#.utf8)
        try bytes.write(to: persistence.url)

        let loaded = try XCTUnwrap(persistence.load().conversations)
        XCTAssertEqual(loaded.first?.title, L.defaultTitle)
        XCTAssertEqual(loaded.first?.messages.count, 1)
        XCTAssertFalse(manager.fileExists(atPath: persistence.backup.path),
                       "ein load kostet keine Sicherungskopie")
    }

    func testAnEmptyFileIsNothingToLose() throws {
        let persistence = ConversationFilePersistence(url: url(in: tempDocuments()))
        try Data().write(to: persistence.url)
        XCTAssertEqual(persistence.load(), .nothing)
    }

    func testAHistoryFromTheOldSharedPlaceMovesIntoTheNewOne() throws {
        let paths = StoragePaths(documents: tempDocuments())
        try JSONEncoder().encode(fixture("Aus dem alten Ordner")).write(to: paths.storedConversationsBeforeMove)
        let persistence = ConversationFilePersistence(url: paths.conversations,
                                                     legacyURL: paths.storedConversationsBeforeMove)

        let loaded = try XCTUnwrap(persistence.load().conversations)
        XCTAssertEqual(loaded.first?.messages.first?.text, "Aus dem alten Ordner")
        XCTAssertFalse(manager.fileExists(atPath: paths.storedConversationsBeforeMove.path),
                       "the shared folder must not keep a second copy of the history")
    }

    func testAnUnmovableLegacyFileIsLeftAloneInsteadOfEmptied() async throws {
        let paths = StoragePaths(documents: tempDocuments())
        try manager.createDirectory(at: paths.storedConversationsBeforeMove, withIntermediateDirectories: true)
        let persistence = ConversationFilePersistence(url: paths.conversations,
                                                     legacyURL: paths.storedConversationsBeforeMove)

        XCTAssertEqual(persistence.load(), .nothing)
        XCTAssertTrue(manager.fileExists(atPath: paths.storedConversationsBeforeMove.path),
                      "a directory is not a history, so it must not be moved into the store's place")

        try await persistence.persist(fixture("Trotzdem geschrieben"))
        XCTAssertEqual(persistence.load().conversations?.first?.messages.first?.text,
                       "Trotzdem geschrieben", "and the new place stays writable")
    }

    func testTheQuarantinedBytesSurviveTheNextWrite() async throws {
        let dir = tempDocuments()
        let persistence = ConversationFilePersistence(url: url(in: dir))
        let bytes = Data("keine gültige historik".utf8)
        try bytes.write(to: persistence.url)
        let moved = try XCTUnwrap(caseURL(persistence.load()))

        try await persistence.persist(fixture("Neuanfang"))

        XCTAssertEqual(persistence.load().conversations?.count, 1)
        XCTAssertEqual(try Data(contentsOf: moved), bytes)
    }

    func testUnusableTargetPathFailsTheWriteAndStillLoadsNothing() async throws {
        let dir = tempDocuments()
        try manager.createDirectory(at: url(in: dir), withIntermediateDirectories: true)
        let persistence = ConversationFilePersistence(url: url(in: dir))
        do {
            try await persistence.persist(fixture("Frage"))
            XCTFail("Ein Verzeichnis anstelle der Datei kann nicht überschrieben werden")
        } catch {
            XCTAssertEqual(persistence.load(), .nothing)
        }
    }

    func testAMessageWithoutAnyOfTheOptionalFieldsDecodes() throws {
        let legacy = #"""
        [{"id":"6E2A1C4D-5B7F-4A10-9C8D-0E1F2A3B4C5D","title":"alt","updatedAt":800000000,
          "messages":[{"id":"6E2A1C4D-5B7F-4A10-9C8D-0E1F2A3B4C5E","role":"assistant","text":"halli hallo",
                       "images":[],"date":800000000}]}]
        """#
        let loaded = try JSONDecoder().decode([Conversation].self, from: Data(legacy.utf8))
        XCTAssertEqual(loaded.first?.messages.first?.text, "halli hallo")
        XCTAssertNil(loaded.first?.messages.first?.placeGroups)
    }

    func testAMessageWithFieldsTheAppNeverHeardOfDecodes() throws {
        let future = #"""
        [{"title":"morgen","messages":[{"role":"user","text":"heute","unbekanntesFeld":42,
                                        "images":[{"file":"bild.jpg","marke":null}]}],
          "unbekannteEigenschaft":"x"}]
        """#
        let loaded = try JSONDecoder().decode([Conversation].self, from: Data(future.utf8))
        XCTAssertEqual(loaded.first?.messages.first?.text, "heute")
        XCTAssertEqual(loaded.first?.messages.first?.images.map(\.file), ["bild.jpg"])
    }

    func testAStoredShapeThatIsNotTheRightTypeFallsBackInsteadOfThrowing() throws {
        let broken = #"""
        [{"title":null,"messages":[{"role":"assistant","text":"text ok","date":"vorgestern",
                                    "images":"keine liste","thinking":7,"outImages":[{"file":17}]}]}]
        """#
        let loaded = try JSONDecoder().decode([Conversation].self, from: Data(broken.utf8))
        let message = try XCTUnwrap(loaded.first?.messages.first)
        XCTAssertEqual(loaded.first?.title, L.defaultTitle, "ein null-Titel fällt auf den Standard zurück")
        XCTAssertEqual(message.text, "text ok")
        XCTAssertTrue(Calendar.current.isDateInToday(message.date), "ein unmögliches Datum wird das heute")
        XCTAssertNil(message.thinking)
        XCTAssertEqual(message.images, [], "eine kaputte Bildliste kostet die Bilder, nicht die Nachricht")
        XCTAssertEqual(message.outImages, [], "ein Eintrag ohne Dateinamen fällt heraus")
    }

    func testAPlaceWithAnUnknownOrMissingTravelModeStillDecodes() throws {
        let json = #"[{"name":"REWE","latitude":52.52,"longitude":13.405,"metres":400,"mode":"fliegend"}]"#
        let places = try JSONDecoder().decode([NearbyPlace].self, from: Data(json.utf8))
        XCTAssertEqual(places.first?.mode, .walking)

        let without = #"[{"name":"REWE"}]"#
        let decoded = try JSONDecoder().decode([NearbyPlace].self, from: Data(without.utf8))
        XCTAssertEqual(decoded.first?.mode, .walking)
        XCTAssertNil(decoded.first?.latitude)
    }

    private func caseURL(_ load: ConversationLoad) -> URL? {
        if case .quarantined(let whereAbout) = load { return whereAbout }
        return nil
    }
}
