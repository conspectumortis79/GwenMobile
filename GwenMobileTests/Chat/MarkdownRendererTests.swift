@testable import GwenMobileFeatureCore
import Foundation
import XCTest
import GwenMobileKit

final class MarkdownRendererTests: XCTestCase {

    private func plain(_ text: String) -> String {
        String(MarkdownRenderer.inline(text).characters)
    }

    func testBoldMarkersBecomePresentationIntent() {
        let attr = MarkdownRenderer.inline("das ist **fett** hier")
        XCTAssertEqual(String(attr.characters), "das ist fett hier")
        XCTAssertTrue(attr.runs.contains { $0.inlinePresentationIntent == .stronglyEmphasized })
    }

    func testEmphasisAndInlineCodeMarkersAreConsumed() {
        XCTAssertEqual(plain("a *b* c `d`"), "a b c d")
    }

    func testLinkKeepsItsTargetAndHidesTheURL() {
        let attr = MarkdownRenderer.inline("siehe [Docs](https://example.com/x)")
        XCTAssertTrue(attr.runs.contains { $0.link?.absoluteString == "https://example.com/x" })
        XCTAssertEqual(String(attr.characters), "siehe Docs")
    }

    func testUnterminatedMarkerDegradesToItsPlainText() {
        XCTAssertTrue(plain("noch offen **fett").contains("**"))
    }

    func testParagraphBreaksSurviveTheInlineParser() {
        XCTAssertEqual(plain("zeile 1\n\nzeile 2"), "zeile 1\n\nzeile 2")
    }

    func testEmptyTextStaysEmpty() {
        XCTAssertEqual(plain(""), "")
    }

    func testAHeadingLosesItsHashesAndStandsBold() {
        let attr = MarkdownRenderer.answer("### Gesamtzusammenfassung\nDie Videos zeigen jeweils")
        XCTAssertEqual(String(attr.characters), "Gesamtzusammenfassung\nDie Videos zeigen jeweils")
        XCTAssertTrue(attr.runs.contains {
            String(attr[$0.range].characters) == "Gesamtzusammenfassung"
                && $0.inlinePresentationIntent == .stronglyEmphasized
        })
    }

    func testAHeadingWithoutASpaceAfterTheHashesLosesThemToo() {
        XCTAssertEqual(String(MarkdownRenderer.answer("###Video 1: Eiffelturm").characters),
                       "Video 1: Eiffelturm")
    }

    func testASingleHashWithoutASpaceIsNoHeading() {
        XCTAssertEqual(String(MarkdownRenderer.answer("#1 Punkt").characters), "#1 Punkt")
    }

    func testAHeadingThatAlreadyHoldsBoldKeepsIt() {
        let attr = MarkdownRenderer.answer("### Video **zwei**")
        XCTAssertEqual(String(attr.characters), "Video zwei")
        XCTAssertTrue(attr.runs.contains { $0.inlinePresentationIntent == .stronglyEmphasized })
    }

    func testAsteriskAndPlusBulletsBecomeTheAppsDash() {
        let attr = MarkdownRenderer.answer("* eins\n  + zwei\n* drei")
        XCTAssertEqual(String(attr.characters), "- eins\n  - zwei\n- drei")
    }

    func testAThematicBreakBecomesARule() {
        let made = String(MarkdownRenderer.answer("oben\n\n---\n\nunten").characters)
        XCTAssertFalse(made.contains("---"))
        XCTAssertEqual(made, "oben\n\n" + String(repeating: "\u{2500}", count: 10) + "\n\nunten")
    }

    func testTheUserTextKeepsItsBlockMarkers() {
        XCTAssertEqual(String(MarkdownRenderer.inline("### Titel").characters), "### Titel")
        XCTAssertEqual(String(MarkdownRenderer.inline("* punkt").characters), "* punkt")
    }

    func testTheAnswerKeepsItsParagraphsAroundABlock() {
        XCTAssertEqual(String(MarkdownRenderer.answer("### Titel\n\nAbsatz eins\n\nAbsatz zwei").characters),
                       "Titel\n\nAbsatz eins\n\nAbsatz zwei")
    }

    func testAnAnswerLinksEveryPhoneNumberToItsDialTarget() {
        let attr = MarkdownRenderer.answer("Ruf 0170 1234567 an, sonst 030 123456.", phoneLinks: true)
        let linked = attr.runs.filter { $0.link != nil }
        XCTAssertEqual(linked.map { String(attr[$0.range].characters) }, ["0170 1234567", "030 123456"])
        XCTAssertEqual(linked.compactMap(\.link?.absoluteString), ["tel:01701234567", "tel:030123456"])
    }

    func testWithoutThePhoneSwitchTheTextKeepsItsPlainNumbers() {
        XCTAssertFalse(MarkdownRenderer.inline("Ruf 0170 1234567 an.").runs.contains { $0.link != nil })
    }

    func testATextThatAlreadyHoldsALinkKeepsItInsteadOfADialTarget() {
        let attr = MarkdownRenderer.answer("Ruf [030 123456](https://example.com/x) an.", phoneLinks: true)
        XCTAssertEqual(attr.runs.compactMap(\.link).map(\.absoluteString), ["https://example.com/x"])
    }

    func testAMarkedTelephoneLinkKeepsItsOwnDialTargetAndLooksLikeALink() {
        let attr = MarkdownRenderer.answer("Ruf [Zentrale](tel:+49301234567) an.", phoneLinks: true)
        let linked = attr.runs.filter { $0.link != nil }
        XCTAssertEqual(linked.map { String(attr[$0.range].characters) }, ["Zentrale"])
        XCTAssertEqual(linked.compactMap(\.link?.absoluteString), ["tel:+49301234567"])
        XCTAssertTrue(linked.allSatisfy { $0.foregroundColor == .blue && $0.underlineStyle == .single })
    }

    func testTheModelMayMarkANumberTheScannerWouldNotTouch() {
        let attr = MarkdownRenderer.answer("Notruf [112](tel:112).", phoneLinks: true)
        XCTAssertEqual(attr.runs.compactMap(\.link?.absoluteString), ["tel:112"])
    }

    func testDatesPricesAndPostalCodesInAnAnswerStayUnlinked() {
        let text = "Am 01.01.2024 kostet es 1.299,00 Euro in der PLZ 01067."
        XCTAssertFalse(MarkdownRenderer.answer(text, phoneLinks: true).runs.contains { $0.link != nil })
    }

    @MainActor func testWorstParseOfAGrowingAnswerStaysBelowTheThrottleInterval() {
        let answer = String(repeating: "### Abschnitt\n* Der **Zahnarzt** kostet `50 €` [Details](https://example.com/z) "
            + "und morgen *viel* mehr Text für eine lange Antwort.\n\n---\n\n", count: 12)
        var worst = Duration.zero
        var taken = 0
        while taken < answer.count {
            taken += 220
            let slice = String(answer.prefix(taken))
            let start = ContinuousClock.now
            _ = MarkdownRenderer.answer(slice)
            let spent = start.duration(to: .now)
            if spent > worst { worst = spent }
        }
        let ms = Double(worst.components.seconds) * 1000 + Double(worst.components.attoseconds) / 1e15
        XCTContext.runActivity(named: "worst inline parse \(String(format: "%.2f", ms)) ms "
            + "bei \(answer.utf8.count) Bytes") { _ in
            XCTAssertLessThan(ms, 60, "Ein Parse-Durchlauf darf nicht länger als der Stream-Throttle von 60 ms dauern")
        }
    }
}
