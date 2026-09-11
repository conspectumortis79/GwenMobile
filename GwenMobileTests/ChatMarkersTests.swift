import XCTest
@testable import GwenMobile

final class ChatMarkersTests: XCTestCase {
    func testPlainAnswerNeedsNoRouting() {
        XCTAssertTrue(ChatMarkers.parse("Statistiken sind Zahlenübersichten.").isEmpty)
        XCTAssertTrue(ChatMarkers.parse("").isEmpty)
    }

    func testSingleMarkersAreRecognised() {
        XCTAssertEqual(ChatMarkers.parse("[[SEARCH]]"), RouteDecision(search: true))
        XCTAssertEqual(ChatMarkers.parse("[[CHART]]"), RouteDecision(chart: true))
        XCTAssertEqual(ChatMarkers.parse("  [[CHART]]  "), RouteDecision(chart: true))
    }

    func testCombinedMarkersKeepBothFlags() {
        XCTAssertEqual(ChatMarkers.parse("[[SEARCH]][[CHART]]"),
                       RouteDecision(search: true, chart: true))
        XCTAssertEqual(ChatMarkers.parse("[[CHART]][[SEARCH]]"),
                       RouteDecision(search: true, chart: true))
    }

    func testMarkerOnlyInRunningTextIsIgnored() {
        XCTAssertEqual(ChatMarkers.parse("Hier die Zahlen. [[CHART]] danach kommt nichts mehr."),
                       RouteDecision())
        XCTAssertEqual(ChatMarkers.parse("Ich suche das nach [[SEARCH]]."), RouteDecision())
    }

    func testStripRemovesOnlyLeadingMarkers() {
        XCTAssertEqual(ChatMarkers.strip("[[SEARCH]][[CHART]]Rest"), "Rest")
        XCTAssertEqual(ChatMarkers.strip("[[CHART]]\n\nRest mit [[SEARCH]]"), "Rest mit [[SEARCH]]")
        XCTAssertEqual(ChatMarkers.strip("nichts zu entfernen"), "nichts zu entfernen")
    }
}
