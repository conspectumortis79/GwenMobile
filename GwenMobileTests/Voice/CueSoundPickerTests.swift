@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit

@MainActor
final class CueSoundPickerTests: GwenTestCase {
    func testThePickerDrawsItsSystemSounds() async throws {
        var selection = ""
        let binding = Binding(get: { selection }, set: { selection = $0 })
        let controller = mountView(NavigationStack {
            CueSoundPicker(title: L.t("sent_sound"), selection: binding, tone: .sent)
        }, size: CGSize(width: 390, height: 700))
        try await settleHosted(controller, milliseconds: 700)
        XCTAssertNotNil(controller.view.window)
    }

    func testTheSoundLabels() {
        XCTAssertEqual(CueSoundLabel.name(of: ""), L.t("sound_default"))
        XCTAssertFalse(CueSoundLabel.folder("").isEmpty)
        XCTAssertEqual(CueSoundLabel.folder("UISounds"), "UISounds")
        XCTAssertEqual(CueSoundLabel.name(of: "/System/Library/Audio/UISounds/Tink.caf"),
                       SystemSoundCatalog.name(ofPath: "/System/Library/Audio/UISounds/Tink.caf"))
    }
}
