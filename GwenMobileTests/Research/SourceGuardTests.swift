@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class SourceGuardTests: GwenTestCase {
    private func verdict(_ address: String, reported: Bool = false) -> SourceGuard.Verdict {
        SourceGuard.assess(URL(string: address), reported: reported)
    }

    func testAnOrdinaryAddressIsClear() {
        XCTAssertEqual(verdict("https://www.spiegel.de/politik/x").risk, .clear)
        XCTAssertEqual(verdict("https://de.wikipedia.org/wiki/Berlin").risk, .clear)
    }

    func testAReportedAddressIsBlocked() {
        let reported = verdict("https://example.org/a", reported: true)
        XCTAssertTrue(reported.isBlocked)
        XCTAssertEqual(reported.reasons, [.reported])
    }

    func testAnAddressWithUserinfoIsBlocked() {
        XCTAssertTrue(verdict("https://user@example.org/a").isBlocked)
        XCTAssertTrue(verdict("https://example.org@evil.test/a").isBlocked)
    }

    func testPlainHttpOnlyWarns() {
        let plain = verdict("http://example.org/a")
        XCTAssertEqual(plain.risk, .caution)
        XCTAssertTrue(plain.reasons.contains(.unencrypted))
    }

    func testABareAddressOnlyWarns() {
        let address = verdict("https://93.184.216.34/a")
        XCTAssertTrue(address.reasons.contains(.ipAddress))
        XCTAssertFalse(address.isBlocked)
    }

    func testPunycodeOnlyWarns() {
        let punycode = verdict("https://xn--mnchen-3ya.de/a")
        XCTAssertTrue(punycode.reasons.contains(.punycode))
        XCTAssertFalse(punycode.isBlocked)
        XCTAssertEqual(verdict("https://x--mnchen-3ya.de/a").risk, .clear)
    }

    func testWithoutAnAddressTheGuardOnlyWarns() {
        XCTAssertEqual(SourceGuard.assess(nil, reported: false).risk, .caution)
    }
}
