import UIKit
import XCTest
@testable import GwenMobile

@MainActor
final class ForegroundReturnTrackerTests: XCTestCase {
    @MainActor
    final class ReturnCounter {
        private(set) var count = 0
        func bump() { count += 1 }
    }

    private func leaveForeground() {
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    private func comeBack() {
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    func testReturnIsReportedOnlyAfterTheAppLeftTheForeground() async throws {
        let tracker = AppForegroundReturnTracker()
        let counter = ReturnCounter()
        tracker.start(onReturn: { counter.bump() })
        comeBack()
        try await settle()
        XCTAssertEqual(counter.count, 0, "ohne Abstecher in den Hintergrund darf nichts gemeldet werden")
        leaveForeground()
        comeBack()
        await waitUntil { counter.count == 1 }
        tracker.stop()
    }

    func testStopEndsTheObservation() async throws {
        let tracker = AppForegroundReturnTracker()
        let counter = ReturnCounter()
        tracker.start(onReturn: { counter.bump() })
        leaveForeground()
        comeBack()
        await waitUntil { counter.count == 1 }
        tracker.stop()
        leaveForeground()
        comeBack()
        try await settle()
        XCTAssertEqual(counter.count, 1, "nach stop() darf keine weitere Rueckkehr ankommen")
    }

    func testStartingTwiceStillReportsExactlyOneReturn() async throws {
        let tracker = AppForegroundReturnTracker()
        let counter = ReturnCounter()
        tracker.start(onReturn: { counter.bump() })
        tracker.start(onReturn: { counter.bump() })
        leaveForeground()
        comeBack()
        await waitUntil { counter.count == 1 }
        try await settle()
        XCTAssertEqual(counter.count, 1, "doppelte Beobachtung wuerde das Fenster zweimal schliessen")
        tracker.stop()
    }
}
