@testable import GwenMobileAdapters
import XCTest

final class ChipRowFadesTests: XCTestCase {
    private let content: CGFloat = 726

    func testWithoutAMeasuredViewportNothingFades() {
        XCTAssertEqual(ChipRowFades.of(contentWidth: content, visible: nil), ChipRowFades())
        XCTAssertEqual(ChipRowFades.of(contentWidth: content, visible: .zero), ChipRowFades())
    }

    func testARowThatFitsNeverFades() {
        let fades = ChipRowFades.of(contentWidth: 300, visible: CGRect(x: 0, y: 0, width: 369, height: 24))
        XCTAssertEqual(fades, ChipRowFades())
    }

    func testAtTheStartOnlyTheTrailingEdgeFades() {
        let fades = ChipRowFades.of(contentWidth: content, visible: CGRect(x: 0, y: 0, width: 369, height: 24))
        XCTAssertEqual(fades, ChipRowFades(leading: false, trailing: true))
    }

    func testInTheMiddleBothEdgesFade() {
        let fades = ChipRowFades.of(contentWidth: content, visible: CGRect(x: 180, y: 0, width: 369, height: 24))
        XCTAssertEqual(fades, ChipRowFades(leading: true, trailing: true))
    }

    func testAtTheEndOnlyTheLeadingEdgeFades() {
        let fades = ChipRowFades.of(contentWidth: content,
                                    visible: CGRect(x: content - 369, y: 0, width: 369, height: 24))
        XCTAssertEqual(fades, ChipRowFades(leading: true, trailing: false))
    }
}
