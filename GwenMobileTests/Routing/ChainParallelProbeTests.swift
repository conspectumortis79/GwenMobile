@testable import GwenMobileProbes
import XCTest

@MainActor
final class ChainParallelProbeTests: XCTestCase {
    func testThePicturesFromTheLastRunCountAsEarly() {
        XCTAssertTrue(DebugChainParallelProbe.earlyVisible(arrivals: [35152, 35339, 46545], ms: 46545))
        XCTAssertTrue(DebugChainParallelProbe.earlyVisible(arrivals: [32493, 32812, 48475], ms: 48475))
    }

    func testEverythingArrivingAtTheEndIsNotEarly() {
        XCTAssertFalse(DebugChainParallelProbe.earlyVisible(arrivals: [46545], ms: 46545))
        XCTAssertFalse(DebugChainParallelProbe.earlyVisible(arrivals: [45000], ms: 46545))
    }

    func testWithoutAnyArrivalNothingIsEarly() {
        XCTAssertFalse(DebugChainParallelProbe.earlyVisible(arrivals: [], ms: 46545))
    }

    func testTheMarginIsTheOneTheProbeUsesForTheComparison() {
        XCTAssertEqual(DebugChainParallelProbe.earlyMargin, 2500)
        XCTAssertFalse(DebugChainParallelProbe.earlyVisible(arrivals: [44045], ms: 46545))
        XCTAssertTrue(DebugChainParallelProbe.earlyVisible(arrivals: [44044], ms: 46545))
    }

    func testTheMixedPlanRunsInTwoStages() {
        XCTAssertEqual(DebugChainParallelProbe.mixedStages(), [2, 1])
    }
}
