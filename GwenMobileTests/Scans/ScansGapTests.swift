@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import UIKit
import VisionKit
import XCTest

@MainActor
final class ScansGapTests: GwenTestCase {
    #if !targetEnvironment(macCatalyst)
    func testSmokeTheDocumentScannerDelegatePaths() {
        let scanner = DocumentScannerSystem.shared
        let controller = VNDocumentCameraViewController()
        scanner.documentCameraViewControllerDidCancel(controller)
        scanner.documentCameraViewController(controller,
                                             didFailWithError: NSError(domain: "test", code: 1))
        scanner.documentCameraViewControllerDidCancel(controller)
        _ = scanner.isSupported
    }
    #endif
}

@MainActor
extension ScansGapTests {
    func testTheDefaultScannerStubAnswers() async {
        let scanner = DocumentScanner.shared
        XCTAssertFalse(scanner.isSupported)
        let pages = await scanner.scan()
        XCTAssertNil(pages)
    }

    func testTheBackgroundStubAnswers() async {
        XCTAssertTrue(PriceWatchBackgroundPort.current is StubPriceWatchBackground)
        PriceWatchBackground.register()
        await PriceWatchBackground.scheduleNext()
        await PriceWatchBackgroundPort.current.handle(nil)
        XCTAssertTrue(PriceWatchBackgroundPort.current is StubPriceWatchBackground)
    }
}
