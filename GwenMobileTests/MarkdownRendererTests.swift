import Foundation
import XCTest
@testable import GwenMobile

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
