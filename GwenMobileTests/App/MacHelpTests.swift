#if targetEnvironment(macCatalyst)
import XCTest
@testable import GwenMobileFeatureCore
@testable import GwenMobileSystem
import GwenMobileKit

@MainActor
final class MacHelpTests: XCTestCase {
    func testEveryHelpTextIsTranslated() {
        var keys = ["mac_help_menu", "mac_help_title", "mac_help_intro", "mac_help_close",
                    "mac_help_keys_head", "mac_help_key_quit", "mac_help_key_help"]
        for section in MacHelpView.sectionKeys {
            keys.append(section + "_head")
            keys.append(section + "_body")
        }
        for key in keys {
            XCTAssertNotEqual(L.t(key), key, "fehlende Übersetzung: \(key)")
        }
    }

    func testOpeningTheHelpCountsUp() {
        let before = MacHelpRequests.shared.token
        MacHelpRequests.shared.open()
        XCTAssertEqual(MacHelpRequests.shared.token, before + 1)
    }
}
#endif
