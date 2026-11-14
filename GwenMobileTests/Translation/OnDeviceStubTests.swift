@testable import GwenMobileFeatureCore
import GwenMobileKit
import XCTest

@MainActor
final class OnDeviceStubTests: GwenTestCase {
    func testTheDeviceTranslationStubReportsUnsupported() async {
        let job = TranslationJob(text: "Hallo", targetCode: "fr")
        let status = await OnDeviceTranslation.status(for: job)
        XCTAssertEqual(status, .unsupportedPair)
        let codes = await OnDeviceTranslation.supportedCodes()
        XCTAssertTrue(codes.isEmpty)
        do {
            _ = try await OnDeviceTranslation.batch(["Hallo"], Locale.Language(identifier: "de"),
                                                     Locale.Language(identifier: "fr"))
            XCTFail("erwartet Fehler")
        } catch {}
    }
}
