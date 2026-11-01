@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class DialNumberTests: XCTestCase {
    func testTheUsualWaysOfWritingANumberKeepOnlyWhatIsDialled() {
        XCTAssertEqual(DialNumber("+49 (170) 222-2222")?.digits, "+491702222222")
        XCTAssertEqual(DialNumber("0170/2222222")?.digits, "01702222222")
        XCTAssertEqual(DialNumber("0049 170 2222222")?.digits, "00491702222222")
        XCTAssertEqual(DialNumber("+49\u{00A0}170.222.2222")?.digits, "+491702222222")
        XCTAssertEqual(DialNumber("  030 12345 ")?.digits, "03012345")
    }

    func testControlCodesAndLettersAreNeverDialled() {
        XCTAssertNil(DialNumber("*31#0170 2222222"), "Apple wählt keine Nummern mit * oder #")
        XCTAssertNil(DialNumber("0170 2222222#"))
        XCTAssertNil(DialNumber("0800-FLOWERS"))
        XCTAssertNil(DialNumber("0170 2222222,123"), "Pausen und Durchwahl-Zeichen bleiben draußen")
        XCTAssertNil(DialNumber("+49+170"))
        XCTAssertNil(DialNumber("٠١٧٠٢٢٢٢٢٢٢"), "nur ASCII-Ziffern gehen an die Telefonie")
    }

    func testTooShortOrEmptyIsNoNumber() {
        XCTAssertNil(DialNumber(""))
        XCTAssertNil(DialNumber("+"))
        XCTAssertNil(DialNumber("12"))
        XCTAssertNotNil(DialNumber("123"))
    }

    func testThePhoneLinkCarriesExactlyTheCleanNumber() {
        XCTAssertEqual(DialNumber("+49 170 2222222")?.telURL?.absoluteString, "tel:+491702222222")
    }

    func testTheMaskedFormShowsOnlyTheLastTwoDigits() {
        let masked = DialNumber("+49 170 2222212")?.masked ?? ""
        XCTAssertTrue(masked.hasSuffix("12"), masked)
        XCTAssertFalse(masked.contains("170"), masked)
        XCTAssertEqual(masked.count, "+491702222212".count)
    }
}
