@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class ChainGateTests: GwenTestCase {
    private func store() -> ChatStore {
        let paths = StoragePaths(documents: tempDocuments())
        return ChatStore(media: MediaStore(paths: paths), paths: paths)
    }

    func testALaterStepWaitsUntilTheEarlierOneHasWritten() {
        let writer = ChainMessageWriter()
        let written = LockedValue<[String]>([])
        writer.commit(step: 1) { written.mutate { $0.append("zwei") } }
        XCTAssertEqual(written.current, [], "der zweite Wunsch schreibt nicht vor dem ersten")
        writer.commit(step: 0) { written.mutate { $0.append("eins") } }
        XCTAssertEqual(written.current, ["eins"], "der zweite Wunsch wartet, bis der erste fertig ist")
        writer.finish(step: 0)
        XCTAssertEqual(written.current, ["eins", "zwei"], "die Reihenfolge bleibt die des Nutzers")
        writer.finish(step: 1)
    }

    func testAFinishedPictureShowsUpBeforeItsTurnAndOnlyOnce() throws {
        let store = store()
        let convID = try XCTUnwrap(store.currentID)
        let started = Date()
        let writer = ChainMessageWriter()
        let late = AnswerSlot(writer: writer, step: 2)
        let picture = AnswerPiece(text: "", artifacts: AnswerArtifacts(outImages: [Attachment(file: "b.jpg")]),
                                  model: "bild", step: late.step)
        late.showNow(picture, to: store, convID: convID, started: started)
        XCTAssertEqual(store.current?.messages.count, 1, "das fertige Bild steht sofort in der Blase")
        XCTAssertEqual(store.current?.messages.last?.outImages?.map(\.file), ["b.jpg"])
        XCTAssertEqual(store.current?.messages.last?.model, "bild")

        let first = AnswerSlot(writer: writer, step: 0)
        first.store(AnswerPiece(text: "Antwort",
                                artifacts: AnswerArtifacts(outImages: [Attachment(file: "a.jpg")])),
                    to: store, convID: convID, started: started)
        XCTAssertEqual(store.current?.messages.count, 1)
        XCTAssertEqual(store.current?.messages.last?.outImages?.map(\.file), ["a.jpg", "b.jpg"],
                       "sobald der Schritt dran ist, richtet sich die Reihenfolge nach den Wünschen")

        late.commit {
            late.carry.add(picture)
            writer.forget(step: 2)
            writer.flush(to: store, convID: convID, started: started)
        }
        XCTAssertEqual(store.current?.messages.last?.outImages?.map(\.file), ["a.jpg", "b.jpg"],
                       "das Bild steht nur einmal in der Blase")
    }

    func testASeparateBubbleChainNeverShowsAPieceAheadOfItsTurn() throws {
        let store = store()
        let convID = try XCTUnwrap(store.currentID)
        let writer = ChainMessageWriter()
        let slot = AnswerSlot(writer: writer, writes: false, step: 1)
        let picture = AnswerPiece(text: "", artifacts: AnswerArtifacts(outImages: [Attachment(file: "b.jpg")]))
        slot.showNow(picture, to: store, convID: convID, started: Date())
        XCTAssertTrue((store.current?.messages ?? []).isEmpty,
                      "eine eigene Blase wartet auf ihren Platz in der Reihenfolge")
    }

    func testAWriteThatArrivesAfterItsTurnGoesOutAtOnce() {
        let writer = ChainMessageWriter()
        let written = LockedValue<[String]>([])
        writer.commit(step: 0) { written.mutate { $0.append("eins") } }
        writer.finish(step: 0)
        XCTAssertEqual(written.current, ["eins"])
        writer.commit(step: 0) { written.mutate { $0.append("nachtrag") } }
        XCTAssertEqual(written.current, ["eins", "nachtrag"],
                       "ein Nachtrag nach dem Ende wartet auf niemanden mehr")
        writer.commit(step: 1) { written.mutate { $0.append("zwei") } }
        writer.finish(step: 1)
        XCTAssertEqual(written.current, ["eins", "nachtrag", "zwei"])
    }

    func testSeveralPiecesOfOneStepKeepTheirOwnOrder() {
        let writer = ChainMessageWriter()
        let written = LockedValue<[String]>([])
        writer.commit(step: 0) { written.mutate { $0.append("a") } }
        writer.commit(step: 0) { written.mutate { $0.append("b") } }
        XCTAssertEqual(written.current, ["a", "b"])
    }

    func testAStepThatWritesNothingDoesNotBlockTheNextOne() {
        let writer = ChainMessageWriter()
        let written = LockedValue<[String]>([])
        writer.commit(step: 1) { written.mutate { $0.append("zwei") } }
        writer.finish(step: 0)
        XCTAssertEqual(written.current, ["zwei"], "ein abgebrochener Schritt hält die Kette nicht an")
    }

    func testAStoppedChainStillWritesWhatWasAlreadyProduced() {
        let writer = ChainMessageWriter()
        let written = LockedValue<[String]>([])
        writer.commit(step: 2) { written.mutate { $0.append("drei") } }
        XCTAssertEqual(written.current, [])
        writer.close(upTo: 3)
        XCTAssertEqual(written.current, ["drei"])
        writer.close(upTo: 0)
        XCTAssertEqual(written.current, ["drei"], "ein zweites Schließen schreibt nichts doppelt")
    }

    func testAReviewFindsItsPieceByTheWishItBelongsTo() throws {
        let store = store()
        let convID = try XCTUnwrap(store.currentID)
        let started = Date()
        let writer = ChainMessageWriter()
        let slot = AnswerSlot(writer: writer, step: 4)
        slot.store(AnswerPiece(text: "Erste Antwort [1].",
                               artifacts: AnswerArtifacts(sources: [WebSource(title: "a", url: "https://a.test",
                                                                              domain: "a.test")])),
                   to: store, convID: convID, started: started)
        let first = AnswerPlacement(messageID: nil, slot: slot, convID: convID, started: started)
        XCTAssertTrue(first.applySourceReview(SourceReview(unsupported: ["a"]), to: store))
        XCTAssertEqual(store.current?.messages.last?.sourceReview?.unsupported, ["a"])

        let foreignSlot = AnswerSlot(writer: writer, step: 9)
        let stranger = AnswerPlacement(messageID: nil, slot: foreignSlot, convID: convID, started: started)
        XCTAssertFalse(stranger.applySourceReview(SourceReview(unsupported: ["b"]), to: store),
                       "eine fremde Stufe findet kein Stück")
    }

    func testAPlacementHandsItsMessageOutWhenTheWriteHappened() async {
        let placement = AnswerPlacement(messageID: nil, slot: nil,
                                        convID: UUID(), started: Date())
        let waiting = Task { await placement.resolvedMessageID() }
        let messageID = UUID()
        placement.settle(messageID)
        let resolved = await waiting.value
        XCTAssertEqual(resolved, messageID)
        XCTAssertEqual(placement.messageID, messageID)
        placement.settle(UUID())
        XCTAssertEqual(placement.messageID, messageID, "ein zweites Setzen ändert die Nachricht nicht mehr")
        let again = await placement.resolvedMessageID()
        XCTAssertEqual(again, messageID)
    }

    func testAPlacementWithoutAMessageStaysEmpty() async {
        let placement = AnswerPlacement(messageID: nil, slot: nil,
                                        convID: UUID(), started: Date())
        placement.settle(nil)
        let empty = await placement.resolvedMessageID()
        XCTAssertNil(empty)
        let known = AnswerPlacement(messageID: UUID(), slot: nil, convID: UUID(), started: Date())
        let settled = await known.resolvedMessageID()
        XCTAssertNotNil(settled)
    }

    func testAReviewForAWholeStepWithoutAStepNumberFindsNothing() {
        let unnumbered = AnswerCarry()
        unnumbered.add(AnswerPiece(text: "Antwort"))
        XCTAssertFalse(unnumbered.setSourceReview(SourceReview(), forStep: 0))

        let carry = AnswerCarry()
        carry.add(AnswerPiece(text: "Antwort", step: 0))
        XCTAssertFalse(carry.setSourceReview(SourceReview(), forStep: nil))
        XCTAssertFalse(carry.setSourceReview(SourceReview(), forStep: 7))
        XCTAssertTrue(carry.setSourceReview(SourceReview(), forStep: 0))
    }

    func testTheVisibleStreamBelongsToTheFirstStepThatStarted() {
        let lease = StreamLease()
        XCTAssertFalse(lease.isBusy)
        XCTAssertTrue(lease.begin(2))
        XCTAssertTrue(lease.isBusy)
        XCTAssertFalse(lease.begin(3), "der zweite Strom schreibt nicht in dieselbe Vorschau")
        XCTAssertTrue(lease.begin(2), "derselbe Schritt behält seine Vorschau")
        lease.end(3)
        XCTAssertTrue(lease.isBusy, "der erste Schritt streamt weiter")
        lease.end(2)
        XCTAssertFalse(lease.isBusy)
        XCTAssertTrue(lease.begin(3), "nach dem Ende übernimmt der nächste Schritt")
        lease.end(3)
        XCTAssertFalse(lease.isBusy)
    }

    func testTheStatusLineShowsTheEarliestStepThatIsStillWorking() {
        let ledger = StatusLedger()
        XCTAssertNil(ledger.text)
        ledger.show("suche", for: 2)
        XCTAssertEqual(ledger.text, "suche")
        ledger.show("bilder", for: 1)
        XCTAssertEqual(ledger.text, "bilder", "der frühere Wunsch bestimmt die Zeile")
        ledger.show("lädt", for: 1)
        XCTAssertEqual(ledger.text, "lädt")
        ledger.clear(1)
        XCTAssertEqual(ledger.text, "suche")
        ledger.clear(1)
        XCTAssertEqual(ledger.text, "suche", "ein zweites Löschen lässt die andere Zeile stehen")
        ledger.clear(2)
        XCTAssertNil(ledger.text)
    }

    func testTheRunnerStopsEveryLiveAnswerAtOnce() async {
        let ended = LockedValue(0)
        let runner = ChatRunner { _ in
            AsyncThrowingStream { continuation in
                continuation.yield("teil")
                continuation.onTermination = { _ in ended.mutate { $0 += 1 } }
            }
        }
        let first = Task {
            try await runner.run(URLRequest(url: URL(string: "https://x.test/eins")!), onChunk: { _ in })
        }
        let second = Task {
            try await runner.run(URLRequest(url: URL(string: "https://x.test/zwei")!), onChunk: { _ in })
        }
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(ended.current, 0)
        runner.cancelAll()
        for _ in 0..<40 where ended.current < 2 {
            try? await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(ended.current, 2, "beide laufenden Antworten werden abgebrochen")
        first.cancel()
        second.cancel()
    }
}
