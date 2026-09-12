import UIKit
import XCTest
@testable import GwenMobile

@MainActor
final class RecordingCloser: SharePresentationClosing {
    private(set) var closeCount = 0

    func close() { closeCount += 1 }
}

@MainActor
final class FakeForeground: ForegroundReturnTracking {
    var onStart: (() -> Void)?
    private(set) var stopCount = 0
    private var onReturn: (@MainActor () -> Void)?

    func start(onReturn: @escaping @MainActor () -> Void) {
        self.onReturn = onReturn
        onStart?()
    }

    func stop() {
        stopCount += 1
        onReturn = nil
    }

    func returnToForeground() { onReturn?() }
}

@MainActor
final class ShareSessionTests: XCTestCase {
    private func makeSession(policy: ShareHandoverPolicy = ShareHandoverPolicy())
        -> (ShareSession, RecordingCloser, FakeForeground) {
        let closer = RecordingCloser()
        let foreground = FakeForeground()
        return (ShareSession(closer: closer, foreground: foreground, policy: policy), closer, foreground)
    }

    func testAirDropHandoverTearsThePresentationDownAtOnce() {
        let (session, closer, foreground) = makeSession()
        session.noteHandover(.airDrop)
        XCTAssertEqual(closer.closeCount, 1, "nach der AirDrop-Uebergabe muss die Freigabe-Kette zu sein")
        XCTAssertEqual(foreground.stopCount, 1, "die Beobachtung des Programmwechsels muss mit beendet werden")
    }

    func testHandoverOfAnyOtherActivityKeepsThePresentationOpen() {
        let (session, closer, foreground) = makeSession()
        session.noteHandover(.message)
        session.noteHandover(UIActivity.ActivityType(rawValue: "com.example.ShareExtension"))
        XCTAssertEqual(closer.closeCount, 0, "vor der Uebergabe an eine andere App muss die Auswahl sichtbar bleiben")
        XCTAssertEqual(foreground.stopCount, 0)
    }

    func testPlaceholderRequestWithoutActivityTypeChangesNothing() {
        let (session, closer, _) = makeSession()
        session.noteHandover(nil)
        XCTAssertEqual(closer.closeCount, 0)
    }

    func testComingBackToTheForegroundAfterAHandoverTearsThePresentationDown() {
        let (session, closer, foreground) = makeSession()
        session.noteHandover(.mail)
        foreground.returnToForeground()
        XCTAssertEqual(closer.closeCount, 1, "zurueck in der App muss wieder der Chat zu sehen sein")
    }

    func testComingBackToTheForegroundWithoutAHandoverKeepsThePresentationOpen() {
        let (session, closer, foreground) = makeSession()
        session.noteHandover(nil)
        foreground.returnToForeground()
        XCTAssertEqual(closer.closeCount, 0, "ein Programmwechsel mitten in der Auswahl darf das Fenster nicht zubauen")
    }

    func testSystemCompletionTearsThePresentationDown() {
        let (session, closer, _) = makeSession()
        session.noteSystemCompletion()
        XCTAssertEqual(closer.closeCount, 1)
    }

    func testActivityWithItsOwnPickerClosesOnSystemCompletion() {
        let (session, closer, _) = makeSession()
        session.noteHandover(.print)
        session.noteSystemCompletion()
        XCTAssertEqual(closer.closeCount, 1)
    }

    func testThePresentationIsNeverTornDownTwice() {
        let (session, closer, foreground) = makeSession()
        session.noteHandover(.airDrop)
        session.noteSystemCompletion()
        foreground.returnToForeground()
        session.noteHandover(.airDrop)
        XCTAssertEqual(closer.closeCount, 1, "ein bereits geschlossenes Fenster darf nicht zweimal zugegangen werden")
    }

    func testTrackingStartsTogetherWithTheSession() {
        let closer = RecordingCloser()
        let foreground = FakeForeground()
        var started = false
        foreground.onStart = { started = true }
        _ = ShareSession(closer: closer, foreground: foreground)
        XCTAssertTrue(started, "ohne Beobachtung bliebe das Fenster nach WhatsApp und Kollegen stehen")
    }

    func testTheItemSourceReportsTheChosenActivityAndHandsOverTheFile() async throws {
        let (session, closer, _) = makeSession()
        let url = try XCTUnwrap(URL(string: "file:///tmp/antwort.html"))
        let source = session.itemSource(for: url)
        let sheet = UIActivityViewController(activityItems: [source], applicationActivities: nil)
        let handed = try XCTUnwrap(source.activityViewController(sheet, itemForActivityType: .airDrop) as? URL)
        XCTAssertEqual(handed, url)
        await waitUntil { closer.closeCount == 1 }
    }

    func testPolicyOnlyNamesActivitiesThatNeedTheImmediateClose() {
        XCTAssertTrue(ShareHandoverPolicy().closesTheSheet(on: .airDrop))
        XCTAssertFalse(ShareHandoverPolicy().closesTheSheet(on: .mail))
        XCTAssertFalse(ShareHandoverPolicy().closesTheSheet(on: .message))
        XCTAssertFalse(ShareHandoverPolicy().closesTheSheet(on: nil))
        XCTAssertTrue(ShareHandoverPolicy(closesOnHandover: [.print]).closesTheSheet(on: .print))
        XCTAssertFalse(ShareHandoverPolicy(closesOnHandover: [.print]).closesTheSheet(on: .airDrop))
        XCTAssertEqual(ShareHandoverPolicy(), ShareHandoverPolicy())
        XCTAssertNotEqual(ShareHandoverPolicy(), ShareHandoverPolicy(closesOnHandover: []))
    }
}
