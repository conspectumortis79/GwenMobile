@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class AppInfoTests: GwenTestCase {
    private func info() -> AppInfo {
        AppInfo(info: [
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
        ])
    }

    func testTheBundleValuesAreRead() {
        let app = info()
        XCTAssertEqual(app.version, "1.0")
        XCTAssertEqual(app.build, "1")
        XCTAssertEqual(app.versionLine, "1.0 (Build 1)")
    }

    func testABuildEqualToTheVersionIsNotRepeated() {
        let app = AppInfo(info: ["CFBundleShortVersionString": "1.0", "CFBundleVersion": "1.0"])
        XCTAssertEqual(app.versionLine, "1.0")
    }

    func testTheVersionFallsBackToTheDefault() {
        let app = AppInfo(info: ["CFBundleShortVersionString": "  "])
        XCTAssertEqual(app.version, "1.0")
        XCTAssertNil(app.build)
    }
}
