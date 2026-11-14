@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class ChatMarkersTests: XCTestCase {
    func testPlainAnswerNeedsNoRouting() {
        XCTAssertFalse(ChatMarkers.parse("Statistiken sind Zahlenübersichten.").search)
        XCTAssertFalse(ChatMarkers.parse("").search)
    }

    func testSingleMarkerIsRecognised() {
        XCTAssertEqual(ChatMarkers.parse("[[SEARCH]]"), RouteDecision(search: true))
        XCTAssertEqual(ChatMarkers.parse("  [[SEARCH]]  "), RouteDecision(search: true))
    }

    func testMarkersSurviveMarkdownDecorationInFrontOfThem() {
        XCTAssertEqual(ChatMarkers.parse("- [[SEARCH]]"), RouteDecision(search: true))
        XCTAssertEqual(ChatMarkers.parse("> `[[SEARCH]]`"), RouteDecision(search: true))
    }

    func testMarkerAnywhereInTheAnswerTriggersTheProtocol() {
        XCTAssertEqual(ChatMarkers.parse("Ich suche das nach [[SEARCH]]."), RouteDecision(search: true))
        XCTAssertEqual(ChatMarkers.parse("[[SEARCH]]"), RouteDecision(search: true))
    }

    func testStripRemovesTheMarkerAndTidiesTheSentence() {
        XCTAssertEqual(ChatMarkers.strip("[[SEARCH]]Rest"), "Rest")
        XCTAssertEqual(ChatMarkers.strip("Ich suche das nach [[SEARCH]]."), "Ich suche das nach.")
        XCTAssertEqual(ChatMarkers.strip("[[SEARCH]]\n\nRest"), "Rest")
    }

    func testTextWithoutAMarkerIsReturnedUnchanged() {
        XCTAssertEqual(ChatMarkers.strip("nichts zu entfernen"), "nichts zu entfernen")
        XCTAssertEqual(ChatMarkers.strip("- Aufzählung bleibt\n- zweite Zeile"), "- Aufzählung bleibt\n- zweite Zeile")
    }

    func testStripKeepsWhatTheAnswerItselfPutAtTheEdges() {
        XCTAssertEqual(ChatMarkers.strip("[[SEARCH]] - Aufzählung eins"), "- Aufzählung eins")
        XCTAssertEqual(ChatMarkers.strip("[[SEARCH]] „Zitat“"), "„Zitat“")
        XCTAssertEqual(ChatMarkers.strip("[[SEARCH]] *kursiv* bleibt"), "*kursiv* bleibt")
    }

    func testStripDropsALineThatOnlyEverCarriedTheMarker() {
        XCTAssertEqual(ChatMarkers.strip("* [[SEARCH]]"), "")
        XCTAssertEqual(ChatMarkers.strip("> `[[SEARCH]]`"), "")
    }
}
