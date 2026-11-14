@testable import GwenMobileFeatureCore
import GwenMobileKit
import XCTest

@MainActor
final class ProbeSettingsGuardTests: GwenTestCase {
    func testAProbeRunGivesBackTheSettingsItChanged() {
        let settings = AppSettings.shared
        let before = settings.autoOCR
        let snapshot = ProbeSettingsGuard.begin(settings, probe: "einheit")
        settings.autoOCR.toggle()
        ProbeSettingsGuard.restore(snapshot, to: settings)
        XCTAssertEqual(settings.autoOCR, before)
    }

    func testTheBackupOfAnInterruptedProbeIsRestoredOnlyOnce() {
        let settings = AppSettings.shared
        let before = settings.autoOCR
        _ = ProbeSettingsGuard.begin(settings, probe: "abgebrochen")
        settings.autoOCR.toggle()
        ProbeSettingsGuard.restorePendingIfNeeded(settings)
        XCTAssertEqual(settings.autoOCR, before)
        settings.autoOCR.toggle()
        ProbeSettingsGuard.restorePendingIfNeeded(settings)
        XCTAssertNotEqual(settings.autoOCR, before)
    }

    func testTheRestoreReportsProviderAndProfileDrift() {
        let settings = AppSettings.shared
        settings.profiles.removeValue(forKey: .deepSeek)
        let before = settings.provider
        settings.updateProfile(of: before) { _ in }
        let snapshot = ProbeSettingsGuard.begin(settings, probe: "drift")
        settings.updateProfile(of: before) { $0.chatModel = "drift-model" }
        settings.updateProfile(of: .deepSeek) { $0.chatModel = "neu" }
        settings.provider = .deepSeek
        ProbeSettingsGuard.restore(snapshot, to: settings)
        XCTAssertEqual(settings.provider, before)
        XCTAssertNil(settings.profiles[.deepSeek])
    }
}
