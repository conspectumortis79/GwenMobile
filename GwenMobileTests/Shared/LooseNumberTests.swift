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

    func testFoldedReadsThreeDigitGroupsAsThousands() {
        XCTAssertEqual(LooseNumber.folded("1.234"), "1234")
        XCTAssertEqual(LooseNumber.folded("-1.234"), "-1234")
        XCTAssertEqual(LooseNumber.folded("1.234.567"), "1234567")
        XCTAssertEqual(LooseNumber.folded("1,234,567"), "1234567")
        XCTAssertEqual(LooseNumber.folded("0.125"), "0.125")
        XCTAssertEqual(LooseNumber.folded("12345.678"), "12345.678")
        XCTAssertEqual(LooseNumber.folded("1,234"), "1234")
        XCTAssertEqual(LooseNumber.folded("12,345"), "12345")
        XCTAssertEqual(LooseNumber.folded("0,125"), "0.125")
        XCTAssertEqual(LooseNumber.value("1,500"), 1500)
    }

    func testFoldedReadsDigitsOfOtherScripts() {
        XCTAssertEqual(LooseNumber.folded("\u{0661}\u{0662}\u{0663}\u{0664}"), "1234")
        XCTAssertEqual(LooseNumber.folded("\u{FF11}\u{FF12},\u{FF15}\u{FF10}"), "12.50")
        XCTAssertEqual(LooseNumber.value("\u{0664}\u{0662}"), 42)
        XCTAssertEqual(LooseNumber.value("\u{0661}\u{0662}.\u{0663}\u{0664}\u{0665},\u{0665}\u{0660} \u{20AC}"), 12345.5)
    }

    func testValueReadsAGermanThousandPrice() {
        XCTAssertEqual(LooseNumber.value("1.234"), 1234)
        XCTAssertEqual(LooseNumber.value("1.234 €"), 1234)
        XCTAssertEqual(LooseNumber.value("-1.234,50 €"), -1234.5)
    }

    func testLooseNumberRejectsBooleans() throws {
        XCTAssertNil(LooseNumber.value(true))
        XCTAssertNil(LooseNumber.value(false))
        let raw = Data(#"{"yes":true,"no":false,"zero":0,"one":1}"#.utf8)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        XCTAssertNil(LooseNumber.value(parsed["yes"]))
        XCTAssertNil(LooseNumber.value(parsed["no"]))
        XCTAssertEqual(LooseNumber.value(parsed["zero"]), 0)
        XCTAssertEqual(LooseNumber.value(parsed["one"]), 1)
    }
}
