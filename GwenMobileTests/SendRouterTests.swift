import XCTest
@testable import GwenMobile

final class SendRouterTests: XCTestCase {
    override func setUp() {
        super.setUp()
        L.apply(.de)
    }

    private func attached(_ intent: ImageRoute?) -> SendContext {
        SendContext(attachedImage: true, intent: intent)
    }

    private func remembered(_ intent: ImageRoute? = nil) -> SendContext {
        SendContext(rememberedImage: true, intent: intent)
    }

    func testEditIntentKeepsEditing() {
        XCTAssertEqual(SendRouter.route(text: "färbe die maus blau", context: attached(.edit)), .imageEdit)
    }

    func testCreateIntentRegeneratesWithoutInputImage() {
        XCTAssertEqual(SendRouter.route(text: "mache einen hintergrund wie gemalt",
                                        context: attached(.create)), .imageCreate)
    }

    func testChatIntentStaysInChat() {
        XCTAssertEqual(SendRouter.route(text: "was ist das für ein tier?", context: attached(.chat)), .chat)
    }

    func testMissingIntentWithImageAndEmptyTextIsChat() {
        XCTAssertEqual(SendRouter.route(text: "", context: attached(nil)), .chat)
        XCTAssertEqual(SendRouter.route(text: "mache das bild heller", context: attached(nil)), .chat)
    }

    func testMissingIntentFallsBackToCreationHeuristic() {
        XCTAssertEqual(SendRouter.route(text: "erzeuge ein poster", context: attached(nil)), .imageCreate)
    }

    func testEditHeuristicBlocksCreationFallback() {
        XCTAssertEqual(SendRouter.route(text: "male das bild, aber ändere nur den rahmen",
                                       context: attached(nil)), .chat)
    }

    func testTextOnlyCreationRequestRoutesToImageModel() {
        XCTAssertEqual(SendRouter.route(text: "generate a logo", context: SendContext()), .imageCreate)
    }

    func testCalendarRequestNeedsTextWithoutImage() {
        XCTAssertEqual(SendRouter.route(text: "leg einen termin morgen an", context: SendContext()), .calendar)
        XCTAssertEqual(SendRouter.route(text: "leg einen termin morgen an", context: attached(.chat)), .chat)
    }

    func testCreateIntentForARememberedPictureStillEditsWordsThatDescribeAnEdit() {
        XCTAssertEqual(SendRouter.route(text: "mache den gegenstand aus dem vierten foto so groß wie den aus dem ersten",
                                        context: remembered(.create)), .imageEdit)
        XCTAssertEqual(SendRouter.route(text: "erzeuge ein poster von einem drachen",
                                        context: remembered(.create)), .imageCreate)
    }

    func testACreationWordWithAnEditMeaningStillEditsTheRememberedPicture() {
        XCTAssertEqual(SendRouter.route(text: "Nimm die Farbe vom vierten Bild und male das erste Bild damit an.",
                                        context: remembered(nil)), .imageEdit)
        XCTAssertEqual(SendRouter.route(text: "male ein bild von einem sonnenuntergang",
                                        context: remembered(nil)), .imageCreate)
    }

    func testIntentIsIgnoredWhenDetectionDidNotRun() {
        XCTAssertEqual(SendRouter.route(text: "extrahiere den text", context: SendContext()), .chat)
    }

    func testSearchMarkerTokenMatchesPromptInstruction() {
        XCTAssertTrue(L.t("web_search_prompt").contains(SearchMarker.token))
    }

    func testExplicitChartOfDataWinsOverPlainImageHeuristics() {
        XCTAssertEqual(SendRouter.route(text: "such im internet nach den einwohnerzahlen und stell sie als diagramm dar",
                                        context: SendContext()), .chart(webData: true))
        XCTAssertEqual(SendRouter.route(text: "erzeuge ein diagramm über die umsatzzahlen",
                                        context: SendContext()), .chart(webData: false))
    }

    func testPlainQuestionsAndOtherFlowsKeepTheirRoute() {
        XCTAssertEqual(SendRouter.route(text: "was sagt die statistik über die bevölkerung?",
                                        context: SendContext()), .chat)
        XCTAssertEqual(SendRouter.route(text: "erzeuge ein bild von einem drachen",
                                        context: SendContext()), .imageCreate)
        XCTAssertEqual(SendRouter.route(text: "leg einen termin morgen an",
                                        context: SendContext()), .calendar)
    }

    func testChartWishOnAPictureIsAChartAndNotAVisionAnswer() {
        XCTAssertEqual(SendRouter.route(text: "stell die zahlen als diagramm dar",
                                        context: attached(.chat)), .chart(webData: false))
        XCTAssertEqual(SendRouter.route(text: "stell die werte aus dem foto als diagramm dar",
                                        context: remembered()), .chart(webData: false))
    }

    func testFollowUpEditOfARememberedPictureNeedsNoClassifier() {
        XCTAssertEqual(SendRouter.route(text: "mach das bild dunkler", context: remembered()), .imageEdit)
    }

    func testRememberedPictureStillAnswersQuestionsInChat() {
        XCTAssertEqual(SendRouter.route(text: "warum ist der himmel dort grau?", context: remembered(.chat)), .chat)
        XCTAssertEqual(SendRouter.route(text: "wer ist auf dem foto zu sehen?", context: remembered()), .chat)
    }

    func testClassifierDecidesForARememberedPicture() {
        XCTAssertEqual(SendRouter.route(text: "irgendwas neues dazu", context: remembered(.create)), .imageCreate)
        XCTAssertEqual(SendRouter.route(text: "und noch heller", context: remembered(.edit)), .imageEdit)
    }

    func testCalendarWishSurvivesARememberedPicture() {
        XCTAssertEqual(SendRouter.route(text: "leg einen termin morgen an", context: remembered()), .calendar)
    }

    func testIntentDetectionRunsOnlyWhereItCanStillChangeTheRoute() {
        XCTAssertTrue(SendRouter.needsIntentDetection(text: "was ist das für ein tier?", context: attached(nil)))
        XCTAssertTrue(SendRouter.needsIntentDetection(text: "mache das bild heller", context: attached(nil)))
        XCTAssertTrue(SendRouter.needsIntentDetection(text: "erzeuge ein poster", context: attached(nil)))
        XCTAssertFalse(SendRouter.needsIntentDetection(text: "stell die zahlen als diagramm dar",
                                                       context: attached(nil)))
        XCTAssertFalse(SendRouter.needsIntentDetection(text: "was ist das für ein tier?", context: SendContext()))
        XCTAssertFalse(SendRouter.needsIntentDetection(text: "", context: attached(nil)))
        XCTAssertFalse(SendRouter.needsIntentDetection(text: "mach das bild dunkler", context: remembered()))
        XCTAssertFalse(SendRouter.needsIntentDetection(text: "leg einen termin morgen an", context: remembered()))
        XCTAssertTrue(SendRouter.needsIntentDetection(text: "warum ist der himmel dort grau?",
                                                      context: remembered()))
    }
}
