@testable import GwenMobileFeatureCore
import XCTest

final class AnswerLengthPlanTests: GwenTestCase {
    private let news = "Aktuelle Meldungen aus Berlin:\n\n- **Theater**: a\n- **Tegut**: b\n- **Wasser**: c\n"
        + "- **Stadtrat**: d\n- Weiter gemeldet: e"

    func testADetailWishCountsTheItemsOfThePreviousAnswer() {
        let history = [ChatMessage(role: .user, text: "bitte die aktuellen Nachrichten aus Berlin anzeigen"),
                       ChatMessage(role: .assistant, text: news),
                       ChatMessage(role: .user, text: "bitte je Meldung mehr Information dazu")]
        XCTAssertEqual(AnswerLengthPlan.fitting(history, detailWish: true), .detailed(items: 5))
    }

    func testWithoutTheRoutersDetailWishTheAnswerStaysCompact() {
        XCTAssertEqual(AnswerLengthPlan.fitting([ChatMessage(role: .user, text: "aktuelle Nachrichten aus Berlin")],
                                                detailWish: false), .compact)
        XCTAssertEqual(AnswerLengthPlan.fitting([], detailWish: false), .compact)
        XCTAssertEqual(AnswerLengthPlan.fitting([], detailWish: true), .compact)
    }

    func testANoteOfAnEarlierChainStepIsNotThePreviousAnswer() {
        let history = [ChatMessage(role: .user, text: "Nachrichten aus Berlin"),
                       ChatMessage(role: .assistant, text: news),
                       ChatMessage(role: .user, text: "Erzähl mehr dazu und trag einen Termin ein"),
                       ChatMessage(role: .assistant, text: "Termin angelegt")]
        XCTAssertEqual(AnswerLengthPlan.fitting(history, detailWish: true), .detailed(items: 5))
    }

    func testADetailWishWithoutAnEarlierListStillGetsRoom() {
        let history = [ChatMessage(role: .user, text: "Erzähl mir ausführlich, was in Berlin passiert ist")]
        XCTAssertEqual(AnswerLengthPlan.fitting(history, detailWish: true), .detailed(items: 0))
    }
}
