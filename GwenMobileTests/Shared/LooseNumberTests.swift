import XCTest
import GwenMobileKit

final class LooseNumberTests: XCTestCase {
    func testFoldedFormats() {
        XCTAssertEqual(LooseNumber.folded("1.234,56 €"), "1234.56")
        XCTAssertEqual(LooseNumber.folded("1,234.56"), "1234.56")
        XCTAssertEqual(LooseNumber.folded("429,99"), "429.99")
        XCTAssertEqual(LooseNumber.folded("-12,5"), "-12.5")
    }

    func testValueAcceptsTheModelShapes() {
        XCTAssertEqual(LooseNumber.value(42), 42)
        XCTAssertEqual(LooseNumber.value(42.5), 42.5)
        XCTAssertEqual(LooseNumber.value(NSNumber(value: 7)), 7)
        XCTAssertEqual(LooseNumber.value("1.234,50"), 1234.5)
        XCTAssertNil(LooseNumber.value([1]))
        XCTAssertNil(LooseNumber.value("zwei"))
    }

    func testFoldedKeepsBothSeparatorOrdersApart() {
        XCTAssertEqual(LooseNumber.folded("1,234.56"), "1234.56")
        XCTAssertEqual(LooseNumber.folded("1.234,56"), "1234.56")
        XCTAssertEqual(LooseNumber.folded("12.5"), "12.5")
        XCTAssertEqual(LooseNumber.folded("keine zahl"), "")
    }

    func testFoldedReadsAThreeDigitDotGroupAsThousands() {
        XCTAssertEqual(LooseNumber.folded("1.234"), "1234")
        XCTAssertEqual(LooseNumber.folded("-1.234"), "-1234")
        XCTAssertEqual(LooseNumber.folded("1.234.567"), "1234567")
        XCTAssertEqual(LooseNumber.folded("1,234,567"), "1234567")
        XCTAssertEqual(LooseNumber.folded("0.125"), "0.125")
        XCTAssertEqual(LooseNumber.folded("12345.678"), "12345.678")
        XCTAssertEqual(LooseNumber.folded("1,234"), "1.234")
    }

    func testValueReadsAGermanThousandPrice() {
        XCTAssertEqual(LooseNumber.value("1.234"), 1234)
        XCTAssertEqual(LooseNumber.value("1.234 €"), 1234)
        XCTAssertEqual(LooseNumber.value("-1.234,50 €"), -1234.5)
    }
}
