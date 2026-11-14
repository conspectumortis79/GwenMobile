@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class TranslationIntentTests: GwenTestCase {
    private var history: [ChatMessage] {
        [ChatMessage(role: .user, text: "Was ist ein Regal?"),
         ChatMessage(role: .assistant, text: "Ein Regal ist ein Möbelstück zum Stellagen von Dingen.")]
    }

    func testTheChatFallbackComesFromTheModelsEmptyTextCall() {
        let leer = ToolDecision(route: .translate(TranslationJob(text: "", targetCode: "pl")))
        let gefüllt = leer.withChatText(excluding: "Übersetze das bitte ins Polnische", history: history)
        guard case .translate(let job) = gefüllt.route else { return XCTFail("Route verloren") }
        XCTAssertTrue(job.fromChat)
        XCTAssertEqual(job.text, "Ein Regal ist ein Möbelstück zum Stellagen von Dingen.")
    }

    func testTheModelsOwnEmptyTextCallIsFilledFromTheChat() {
        let leer = ToolDecision(route: .translate(TranslationJob(text: "", targetCode: "fr")))
        let gefüllt = leer.withChatText(excluding: "Übersetze das ins Französische", history: history)
        guard case .translate(let job) = gefüllt.route else { return XCTFail("Route verloren") }
        XCTAssertEqual(job.targetCode, "fr")
        XCTAssertTrue(job.fromChat)
    }

    func testTheChatFallbackKeepsTheWishAndTheIndependence() {
        var leer = ToolDecision(route: .translate(TranslationJob(text: "", targetCode: "fr")))
        leer.wish = "das bitte auf Franzoesisch"
        leer.standalone = true
        let gefuellt = leer.withChatText(excluding: "und das bitte auf Franzoesisch", history: history)
        XCTAssertEqual(gefuellt.wish, "das bitte auf Franzoesisch")
        XCTAssertTrue(gefuellt.standalone)
        guard case .translate(let job) = gefuellt.route else { return XCTFail("Route verloren") }
        XCTAssertTrue(job.fromChat)
    }

    func testAnEmptyTranslationWithoutEarlierChatStaysUntouched() {
        let decision = ToolDecision(route: .translate(TranslationJob(text: "", targetCode: "fr")))
        let result = decision.withChatText(excluding: "sag", history: [])
        guard case .translate(let kept) = result.route else { return XCTFail("kein Auftrag") }
        XCTAssertTrue(kept.isEmpty)
        XCTAssertFalse(kept.fromChat)
    }

    func testChatTextWithoutAnEarlierMessageStaysEmpty() {
        XCTAssertNil(TranslationIntent.chatText(excluding: "Hallo", in: []))
        let only = [ChatMessage(role: .user, text: "Hallo")]
        XCTAssertNil(TranslationIntent.chatText(excluding: "Hallo", in: only))
    }

    func testFoldMatchesUmlautAndSpelledOutVariants() {
        for written in ["Übersetze", "uebersetze", "ÜBERSETZE", "übersetze"] {
            XCTAssertEqual(TranslationFold.of(written), "ubersetze", written)
        }
        for written in ["französische", "franzoesische", "Französische", "FRANZÖSISCHE"] {
            XCTAssertEqual(TranslationFold.of(written), "franzosische", written)
        }
        XCTAssertEqual(TranslationFold.of("Türkei"), "turkei")
        XCTAssertEqual(TranslationFold.of("Strasse"), TranslationFold.of("Straße"))
    }
}
