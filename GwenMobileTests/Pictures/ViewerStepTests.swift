@testable import GwenMobileFeatureCore
import XCTest

final class ViewerStepTests: XCTestCase {
    func testAStepMovesExactlyOnePicture() {
        XCTAssertEqual(ViewerStep.forward.target(from: 1, count: 4), 2)
        XCTAssertEqual(ViewerStep.back.target(from: 1, count: 4), 0)
    }

    func testAStepAtEitherEndOfTheListStaysPut() {
        XCTAssertNil(ViewerStep.back.target(from: 0, count: 3))
        XCTAssertNil(ViewerStep.forward.target(from: 2, count: 3))
    }

    func testAStepWithoutNeighboursIsRefused() {
        XCTAssertNil(ViewerStep.forward.target(from: 0, count: 1))
        XCTAssertNil(ViewerStep.back.target(from: 0, count: 1))
        XCTAssertNil(ViewerStep.forward.target(from: 0, count: 0))
    }

    func testBothDirectionsPointApart() {
        XCTAssertEqual(ViewerStep.back.delta, -1)
        XCTAssertEqual(ViewerStep.forward.delta, 1)
    }
}
