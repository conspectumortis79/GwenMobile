@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class BubblePhoneLinkTests: XCTestCase {
    func testATelLinkYieldsTheDialableNumber() throws {
        let plain = try XCTUnwrap(URL(string: "tel:+49301234567"))
        XCTAssertEqual(Bubble.telNumber(of: plain)?.digits, "+49301234567")
        let escaped = try XCTUnwrap(URL(string: "tel:030%201234567"))
        XCTAssertEqual(Bubble.telNumber(of: escaped)?.digits, "0301234567")
        let slashes = try XCTUnwrap(URL(string: "tel://+4930123456"))
        XCTAssertEqual(Bubble.telNumber(of: slashes)?.digits, "+4930123456")
    }

    func testOtherSchemesAreNoCall() throws {
        XCTAssertNil(Bubble.telNumber(of: try XCTUnwrap(URL(string: "https://example.com/x"))))
        XCTAssertNil(Bubble.telNumber(of: try XCTUnwrap(URL(string: "gwen-source://1"))))
    }

    func testATelLinkWithoutADialableNumberStaysWithTheSystem() throws {
        XCTAssertNil(Bubble.telNumber(of: try XCTUnwrap(URL(string: "tel:0800-FLOWERS"))))
    }
}
