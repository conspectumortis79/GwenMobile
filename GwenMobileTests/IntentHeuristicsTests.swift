import XCTest
@testable import GwenMobile

final class IntentHeuristicsTests: XCTestCase {
    func testGermanImageCreationIsDetected() {
        XCTAssertTrue(IntentHeuristics.looksLikeImageRequest("Erzeuge ein Bild einer Katze"))
        XCTAssertTrue(IntentHeuristics.looksLikeImageRequest("male ein poster"))
    }

    func testCreationWithoutSubjectIsNotAnImageRequest() {
        XCTAssertFalse(IntentHeuristics.looksLikeImageRequest("Erzeuge mir einen Termin"))
    }

    func testEnglishImageRequestIsDetected() {
        XCTAssertTrue(IntentHeuristics.looksLikeImageRequest("generate a logo"))
    }

    func testGermanBackgroundWordIsDetectedOnLoweredText() {
        XCTAssertTrue(IntentHeuristics.looksLikeEditRequest("hintergrund tauschen"))
        XCTAssertTrue(IntentHeuristics.looksLikeEditRequest("ändere den hintergrund"))
        XCTAssertTrue(IntentHeuristics.looksLikeEditRequest("change the background"))
    }

    func testEditRequestDetection() {
        XCTAssertTrue(IntentHeuristics.looksLikeEditRequest("entferne das wasserzeichen"))
        XCTAssertTrue(IntentHeuristics.looksLikeEditRequest("make it darker"))
        XCTAssertFalse(IntentHeuristics.looksLikeEditRequest("was ist das für ein tier"))
    }

    func testColourTransferBetweenTwoPicturesIsAnEditRequest() {
        XCTAssertTrue(IntentHeuristics.looksLikeEditRequest(
            "nimm die farbe des gegenstands auf dem foto, was ich dir gerade schicke, "
            + "und übertrage es als farbe auf das macbook-foto, was ich dir geschickt habe."))
        XCTAssertTrue(IntentHeuristics.looksLikeEditRequest(
            "Du sollst die Farbe des Silikon-Bauteils, also das zweite Foto nehmen, "
            + "und diese Farbe auf das MacBook übertragen."))
        XCTAssertTrue(IntentHeuristics.looksLikeEditRequest(
            "take the colour of the second photo and paint the first one with it"))
    }

    func testCalendarDetection() {
        XCTAssertTrue(IntentHeuristics.looksLikeCalendarRequest("Leg einen Termin morgen 14 Uhr an"))
        XCTAssertTrue(IntentHeuristics.looksLikeCalendarRequest("erase the meeting with tom"))
        XCTAssertFalse(IntentHeuristics.looksLikeCalendarRequest("Beschreibe das Bild"))
    }
}
