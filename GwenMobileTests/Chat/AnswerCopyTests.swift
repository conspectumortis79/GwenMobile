@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import UIKit
import XCTest
import GwenMobileKit

@MainActor
final class RecordingPasteboard: PasteboardWriting {
    private(set) var writes: [String] = []

    func write(_ text: String) { writes.append(text) }
}

@MainActor
final class AnswerCopyTests: GwenTestCase {
    func testCopyingHandsTheRawAnswerToThePasteboard() {
        let pasteboard = RecordingPasteboard()
        AnswerCopyController(pasteboard: pasteboard).perform("Die Hauptstadt ist **Paris**.")
        XCTAssertEqual(pasteboard.writes, ["Die Hauptstadt ist **Paris**."],
                       "Es kopiert der Rohtext, nicht das gerenderte Ergebnis")
    }

    func testEachTapWritesExactlyOnce() {
        let pasteboard = RecordingPasteboard()
        let controller = AnswerCopyController(pasteboard: pasteboard)
        controller.perform("Antwort")
        controller.perform("Antwort")
        XCTAssertEqual(pasteboard.writes, ["Antwort", "Antwort"])
    }

    func testTheConfirmationAppearsAndFadesAgain() async throws {
        let controller = AnswerCopyController(pasteboard: RecordingPasteboard(),
                                              confirmDuration: .milliseconds(60))
        XCTAssertFalse(controller.confirmed)
        controller.perform("Antwort")
        XCTAssertTrue(controller.confirmed)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(controller.confirmed, "Der Haken muss nach der Bestätigungszeit verschwinden")
    }

    func testAFurtherCopyCancelsTheElderTimer() async throws {
        let controller = AnswerCopyController(pasteboard: RecordingPasteboard(),
                                              confirmDuration: .milliseconds(200))
        controller.perform("erste")
        try await Task.sleep(for: .milliseconds(120))
        controller.perform("zweite")
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertTrue(controller.confirmed, "Nur der letzte Timer darf den Haken zurücksetzen")
    }

    func testTheConfirmationLastsAsLongAsTheMockupPromises() {
        XCTAssertEqual(AnswerCopyController.defaultConfirmDuration, .milliseconds(1600))
    }

    func testTheSystemPasteboardWritesToTheGeneralBoard() {
        SystemPasteboard().write("Gwen")
        XCTAssertEqual(UIPasteboard.general.string, "Gwen")
    }

    func testTheCopyAffordanceIsNamedInBothLanguages() {
        L.apply(.de)
        XCTAssertEqual(L.t("copy_answer"), "Antwort kopieren")
        XCTAssertEqual(L.t("copied"), "Kopiert")
        L.apply(.en)
        XCTAssertEqual(L.t("copy_answer"), "Copy answer")
        XCTAssertEqual(L.t("copied"), "Copied")
    }
}
