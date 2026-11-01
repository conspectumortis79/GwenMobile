@testable import GwenMobileDevice
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

    func testAnAnswerLinksEveryPhoneNumberToItsDialTarget() {
        let attr = MarkdownRenderer.inline("Ruf 0170 1234567 an, sonst 030 123456.", phoneLinks: true)
        let linked = attr.runs.filter { $0.link != nil }
        XCTAssertEqual(linked.map { String(attr[$0.range].characters) }, ["0170 1234567", "030 123456"])
        XCTAssertEqual(linked.compactMap(\.link?.absoluteString), ["tel:01701234567", "tel:030123456"])
    }

    func testWithoutThePhoneSwitchTheTextKeepsItsPlainNumbers() {
        XCTAssertFalse(MarkdownRenderer.inline("Ruf 0170 1234567 an.").runs.contains { $0.link != nil })
    }

    func testATextThatAlreadyHoldsALinkKeepsItInsteadOfADialTarget() {
        let attr = MarkdownRenderer.inline("Ruf [030 123456](https://example.com/x) an.", phoneLinks: true)
        XCTAssertEqual(attr.runs.compactMap(\.link).map(\.absoluteString), ["https://example.com/x"])
    }

    func testAMarkedTelephoneLinkKeepsItsOwnDialTargetAndLooksLikeALink() {
        let attr = MarkdownRenderer.inline("Ruf [Zentrale](tel:+49301234567) an.", phoneLinks: true)
        let linked = attr.runs.filter { $0.link != nil }
        XCTAssertEqual(linked.map { String(attr[$0.range].characters) }, ["Zentrale"])
        XCTAssertEqual(linked.compactMap(\.link?.absoluteString), ["tel:+49301234567"])
        XCTAssertTrue(linked.allSatisfy { $0.foregroundColor == .blue && $0.underlineStyle == .single })
    }

    func testTheModelMayMarkANumberTheScannerWouldNotTouch() {
        let attr = MarkdownRenderer.inline("Notruf [112](tel:112).", phoneLinks: true)
        XCTAssertEqual(attr.runs.compactMap(\.link?.absoluteString), ["tel:112"])
    }

    func testDatesPricesAndPostalCodesInAnAnswerStayUnlinked() {
        let text = "Am 01.01.2024 kostet es 1.299,00 Euro in der PLZ 01067."
        XCTAssertFalse(MarkdownRenderer.inline(text, phoneLinks: true).runs.contains { $0.link != nil })
    }

    @MainActor func testWorstParseOfAGrowingAnswerStaysBelowTheThrottleInterval() {
        let answer = String(repeating: "Der **Zahnarzt** kostet `50 €` [Details](https://example.com/z) "
            + "und morgen *viel* mehr Text für eine lange Antwort.\n\n", count: 12)
        var worst = Duration.zero
        var taken = 0
        while taken < answer.count {
            taken += 220
            let slice = String(answer.prefix(taken))
            let start = ContinuousClock.now
            _ = MarkdownRenderer.inline(slice)
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
