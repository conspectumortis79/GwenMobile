import XCTest
@testable import GwenMobile

final class ProcessingRhythmTests: XCTestCase {
    func testCycleCoversFourPhases() {
        XCTAssertEqual(ProcessingRhythm.cycle, ProcessingRhythm.beat * 4, accuracy: 0.0001)
        XCTAssertEqual(ProcessingRhythm.dotCount, 3)
    }

    func testCycleStartsWithZeroDots() {
        XCTAssertGreaterThan(ProcessingRhythm.hiddenDuration(dotIndex: 1), 0)
    }

    func testDotsAppearInCountingOrder() {
        let hidden = (1...ProcessingRhythm.dotCount).map { ProcessingRhythm.hiddenDuration(dotIndex: $0) }
        XCTAssertEqual(hidden, hidden.sorted(), "Punkte müssen in Zählreihenfolge erscheinen")
        XCTAssertLessThan(hidden.first ?? 0, hidden.last ?? 0)
    }

    func testEveryDotTrackFillsTheWholeCycle() {
        for index in 1...ProcessingRhythm.dotCount {
            let total = ProcessingRhythm.hiddenDuration(dotIndex: index) + ProcessingRhythm.fade
                + ProcessingRhythm.holdDuration(dotIndex: index) + ProcessingRhythm.retract
            XCTAssertEqual(total, ProcessingRhythm.cycle, accuracy: 0.0001, "Track \(index)")
        }
    }

    func testKeyframeDurationsArePositive() {
        for index in 1...ProcessingRhythm.dotCount {
            XCTAssertGreaterThan(ProcessingRhythm.hiddenDuration(dotIndex: index), 0, "hidden \(index)")
            XCTAssertGreaterThan(ProcessingRhythm.holdDuration(dotIndex: index), 0, "hold \(index)")
        }
        XCTAssertGreaterThan(ProcessingRhythm.retract, 0)
        XCTAssertLessThan(ProcessingRhythm.retract, ProcessingRhythm.beat)
        XCTAssertLessThan(ProcessingRhythm.fade, ProcessingRhythm.beat)
    }

    func testLastDotReachesThreeDotsBeforeRetract() {
        let lastVisible = ProcessingRhythm.hiddenDuration(dotIndex: ProcessingRhythm.dotCount) + ProcessingRhythm.fade
        XCTAssertLessThan(lastVisible, ProcessingRhythm.cycle - ProcessingRhythm.retract)
    }
}
