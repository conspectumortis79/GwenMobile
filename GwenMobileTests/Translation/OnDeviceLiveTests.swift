@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class OnDeviceLiveTests: GwenTestCase {
    func testTheLiveBatchReportsAMissingLanguagePair() async {
        let source = Locale.Language(identifier: "de")
        let target = Locale.Language(identifier: "zz")
        do {
            _ = try await OnDeviceTranslation.batch(["Hallo"], source, target)
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }
}
