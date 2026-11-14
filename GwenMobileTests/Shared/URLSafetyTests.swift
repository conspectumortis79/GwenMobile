@testable import GwenMobileFeatureCore
import Foundation
import XCTest

final class URLSafetyTests: XCTestCase {
    private func url(_ text: String) throws -> URL {
        try XCTUnwrap(URL(string: text))
    }

    func testLoopbackPrivateAndLocalNamesAreBlocked() throws {
        let blocked = [
            "http://127.0.0.1/",
            "http://127.1/",
            "http://2130706433/",
            "http://0x7f000001/",
            "http://0177.0.0.1/",
            "http://10.0.0.1/",
            "http://172.16.0.1/",
            "http://172.31.255.255/",
            "http://192.168.1.1/",
            "http://169.254.169.254/",
            "http://100.64.0.1/",
            "http://0.0.0.0/",
            "http://[::1]/",
            "http://[fe80::1]/",
            "http://[fd00::1]/",
            "http://[::ffff:127.0.0.1]/",
            "http://[2001:db8::1]/",
            "http://[64:ff9b::7f00:1]/",
            "http://[64:ff9b:1::7f00:1]/",
            "http://[2002:7f00:1::]/",
            "http://[2001:0000::]/",
            "http://localhost/",
            "http://localhost./",
            "http://localhost%2e/",
            "http://foo.localhost./",
            "http://router.local/",
            "http://router.local./",
            "http://metadata.internal/",
            "http://metadata.internal./",
        ]
        for text in blocked {
            XCTAssertTrue(URLSafety.isLocalOrPrivate(try url(text)), text)
        }
    }

    func testPublicAddressesAndNamesAreAllowed() throws {
        let allowed = [
            "https://93.184.216.34/",
            "https://8.8.8.8/",
            "https://example.org/",
            "https://example.org./",
            "https://xn--mnchen-3ya.de/",
            "https://[2001:4860:4860::8888]/",
        ]
        for text in allowed {
            XCTAssertFalse(URLSafety.isLocalOrPrivate(try url(text)), text)
        }
    }

    func testAddressDetectionCoversShorthandAndIPv6() {
        XCTAssertTrue(URLSafety.isIPAddress("127.0.0.1"))
        XCTAssertTrue(URLSafety.isIPAddress("127.0.0.1."))
        XCTAssertTrue(URLSafety.isIPAddress("127.1"))
        XCTAssertTrue(URLSafety.isIPAddress("2130706433"))
        XCTAssertTrue(URLSafety.isIPAddress("::1"))
        XCTAssertTrue(URLSafety.isIPAddress("127.0.1"))
        XCTAssertFalse(URLSafety.isIPAddress("1.2.3.4.5"))
        XCTAssertFalse(URLSafety.isIPAddress("example.org"))
    }

    func testMissingOrHostlessURLsAreUnsafe() {
        XCTAssertTrue(URLSafety.isLocalOrPrivate(nil))
        XCTAssertTrue(URLSafety.isLocalOrPrivate(URL(fileURLWithPath: "/tmp/x")))
    }

    func testAResolvedPrivateAddressIsBlocked() async throws {
        let original = URLSafety.hostResolver
        defer { URLSafety.hostResolver = original }
        URLSafety.hostResolver = { _ in ["127.0.0.1"] }
        let blocked = await URLSafety.isLocalOrPrivateResolved(try url("https://example.org/"))
        XCTAssertTrue(blocked)
        URLSafety.hostResolver = { _ in ["93.184.216.34"] }
        let allowed = await URLSafety.isLocalOrPrivateResolved(try url("https://example.org/"))
        XCTAssertFalse(allowed)
    }
}
