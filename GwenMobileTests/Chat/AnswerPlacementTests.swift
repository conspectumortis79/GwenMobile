@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class AnswerPlacementTests: XCTestCase {
    private func makeStore() -> ChatStore {
        let paths = StoragePaths(documents: tempDocuments())
        return ChatStore(media: MediaStore(paths: paths), paths: paths)
    }

    private func source(_ domain: String) -> WebSource {
        WebSource(title: domain, url: "https://\(domain)", domain: domain)
    }

    private func review(_ name: String) -> SourceReview {
        SourceReview(sourceDomains: 1, citedClaims: 1,
                     checkedClaims: 1, unsupported: [name], verified: true)
    }

    private func openedConversation(_ store: ChatStore) throws -> UUID {
        store.newConversation()
        return try XCTUnwrap(store.currentID)
    }

    func testAReviewLandsOnTheSameMessageWithoutChangingItsText() throws {
        let store = makeStore()
        let convID = try openedConversation(store)
        let messageID = try XCTUnwrap(store.appendAssistant("Berlin liegt an der Spree [1].",
                                                            model: "probe", elapsed: 1, to: convID,
                                                            sources: [source("a.test")]))
        let before = store.current?.messages.last
        XCTAssertNil(before?.sourceReview)

        let placement = AnswerPlacement(messageID: messageID, slot: nil,
                                        convID: convID, started: Date())
        XCTAssertTrue(placement.applySourceReview(review("Spree"), to: store))

        let after = store.current?.messages.last
        XCTAssertEqual(after?.id, messageID, "die Nachricht darf nicht ersetzt werden")
        XCTAssertEqual(after?.text, before?.text)
        XCTAssertEqual(after?.sourceReview, review("Spree"))
        XCTAssertEqual(store.current?.messages.count, 1)
    }

    func testAReviewForASlotPieceSurvivesAFlushOfTheNextStep() throws {
        let store = makeStore()
        let convID = try openedConversation(store)
        let started = Date()
        let writer = ChainMessageWriter()
        let slot = AnswerSlot(writer: writer)
        let first = try XCTUnwrap(writer.carry.add(AnswerPiece(
            text: "Erster Schritt [1].", artifacts: AnswerArtifacts(sources: [source("a.test")]),
            step: slot.step)))
        writer.flush(to: store, convID: convID, started: started)
        let messageID = try XCTUnwrap(writer.messageID)
        XCTAssertEqual(first, 0)

        let placement = AnswerPlacement(messageID: messageID, slot: slot,
                                        convID: convID, started: started)
        XCTAssertTrue(placement.applySourceReview(review("Schritt"), to: store))
        XCTAssertEqual(store.current?.messages.last?.sourceReview, review("Schritt"))

        writer.carry.add(AnswerPiece(text: "Zweiter Schritt.", artifacts: AnswerArtifacts(), step: 1))
        writer.flush(to: store, convID: convID, started: started)

        XCTAssertEqual(store.current?.messages.count, 1)
        XCTAssertEqual(store.current?.messages.last?.id, messageID)
        XCTAssertEqual(store.current?.messages.last?.sourceReview, review("Schritt"),
                       "der nächste Ketten-Schritt darf die Prüfung nicht verlieren")
        XCTAssertTrue(store.current?.messages.last?.text.contains("Zweiter Schritt") ?? false)
    }

    func testTwoReviewsLandOnTheirOwnMessages() throws {
        let store = makeStore()
        let convID = try openedConversation(store)
        let firstID = try XCTUnwrap(store.appendAssistant("Erste Antwort [1].", model: "probe",
                                                          elapsed: 1, to: convID,
                                                          sources: [source("a.test")]))
        let secondID = try XCTUnwrap(store.appendAssistant("Zweite Antwort [1].", model: "probe",
                                                           elapsed: 1, to: convID,
                                                           sources: [source("b.test")]))
        let firstPlacement = AnswerPlacement(messageID: firstID, slot: nil,
                                             convID: convID, started: Date())
        let secondPlacement = AnswerPlacement(messageID: secondID, slot: nil,
                                              convID: convID, started: Date())

        XCTAssertTrue(secondPlacement.applySourceReview(review("zweite"), to: store))
        XCTAssertTrue(firstPlacement.applySourceReview(review("erste"), to: store))

        let messages = store.current?.messages ?? []
        XCTAssertEqual(messages.first(where: { $0.id == firstID })?.sourceReview, review("erste"))
        XCTAssertEqual(messages.first(where: { $0.id == secondID })?.sourceReview, review("zweite"))
    }

    func testAReviewForAMissingMessageChangesNothing() throws {
        let store = makeStore()
        let convID = try openedConversation(store)
        _ = try XCTUnwrap(store.appendAssistant("Antwort [1].", model: "probe", elapsed: 1, to: convID,
                                                sources: [source("a.test")]))
        let placement = AnswerPlacement(messageID: UUID(), slot: nil,
                                        convID: convID, started: Date())
        XCTAssertFalse(placement.applySourceReview(review("fehlt"), to: store))
        XCTAssertNil(store.current?.messages.last?.sourceReview)
    }
}
