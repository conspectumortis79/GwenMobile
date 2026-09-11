import XCTest
@testable import GwenMobile

final class SendRouterTests: XCTestCase {
    override func setUp() {
        super.setUp()
        L.apply(.de)
    }

    func testEditIntentKeepsEditing() {
        XCTAssertEqual(SendRouter.route(text: "färbe die maus blau", hasImage: true, intent: .edit), .imageEdit)
    }

    func testCreateIntentRegeneratesWithoutInputImage() {
        XCTAssertEqual(SendRouter.route(text: "mache einen hintergrund wie gemalt", hasImage: true, intent: .create), .imageCreate)
    }

    func testChatIntentStaysInChat() {
        XCTAssertEqual(SendRouter.route(text: "was ist das für ein tier?", hasImage: true, intent: .chat), .chat)
    }

    func testMissingIntentWithImageAndEmptyTextIsChat() {
        XCTAssertEqual(SendRouter.route(text: "", hasImage: true, intent: nil), .chat)
        XCTAssertEqual(SendRouter.route(text: "mache das bild heller", hasImage: true, intent: nil), .chat)
    }

    func testMissingIntentFallsBackToCreationHeuristic() {
        XCTAssertEqual(SendRouter.route(text: "erzeuge ein poster", hasImage: true, intent: nil), .imageCreate)
    }

    func testEditHeuristicBlocksCreationFallback() {
        XCTAssertEqual(SendRouter.route(text: "male das bild, aber ändere nur den rahmen",
                                       hasImage: true, intent: nil), .chat)
    }

    func testTextOnlyCreationRequestRoutesToImageModel() {
        XCTAssertEqual(SendRouter.route(text: "generate a logo", hasImage: false, intent: nil), .imageCreate)
    }

    func testCalendarRequestNeedsTextWithoutImage() {
        XCTAssertEqual(SendRouter.route(text: "leg einen termin morgen an", hasImage: false, intent: nil), .calendar)
        XCTAssertEqual(SendRouter.route(text: "leg einen termin morgen an", hasImage: true, intent: .chat), .chat)
    }

    func testIntentIsIgnoredWhenDetectionDidNotRun() {
        XCTAssertEqual(SendRouter.route(text: "extrahiere den text", hasImage: false, intent: nil), .chat)
    }

    func testSearchMarkerTokenMatchesPromptInstruction() {
        XCTAssertTrue(L.t("web_search_prompt").contains(SearchMarker.token))
    }

    func testExplicitChartOfDataWinsOverPlainImageHeuristics() {
        XCTAssertEqual(SendRouter.route(text: "such im internet nach den einwohnerzahlen und stell sie als diagramm dar",
                                        hasImage: false, intent: nil), .chart(webData: true))
        XCTAssertEqual(SendRouter.route(text: "erzeuge ein diagramm über die umsatzzahlen",
                                        hasImage: false, intent: nil), .chart(webData: false))
    }

    func testPlainQuestionsAndOtherFlowsKeepTheirRoute() {
        XCTAssertEqual(SendRouter.route(text: "was sagt die statistik über die bevölkerung?",
                                        hasImage: false, intent: nil), .chat)
        XCTAssertEqual(SendRouter.route(text: "erzeuge ein bild von einem drachen",
                                        hasImage: false, intent: nil), .imageCreate)
        XCTAssertEqual(SendRouter.route(text: "leg einen termin morgen an",
                                        hasImage: false, intent: nil), .calendar)
        XCTAssertEqual(SendRouter.route(text: "stell die zahlen als diagramm dar",
                                        hasImage: true, intent: .chat), .chat)
    }
}
