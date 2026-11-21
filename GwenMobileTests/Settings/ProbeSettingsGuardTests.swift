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

    func testAProbeWritesKeysOnlyIntoItsOwnMemoryVault() {
        let settings = AppSettings.shared
        let provider = settings.provider
        for other in ProviderID.allCases where other != provider { settings.clearKey(for: other) }
        settings.setKey("seed-key", for: provider)
        AppSettings.flushKeySave()
        let before = settings.key(for: provider)
        let snapshot = ProbeSettingsGuard.begin(settings, probe: "schluessel")
        XCTAssertEqual(settings.key(for: provider), before)
        settings.setKey("probe-key", for: provider)
        AppSettings.flushKeySave()
        XCTAssertEqual(settings.key(for: provider), "probe-key")
        settings.clearKey(for: provider)
        AppSettings.flushKeySave()
        XCTAssertEqual(settings.key(for: provider), "")
        ProbeSettingsGuard.restore(snapshot, to: settings)
        XCTAssertEqual(settings.key(for: provider), before)
    }

    func testARestoreWithoutASavedVaultLeavesTheKeysAlone() {
        let settings = AppSettings.shared
        let provider = settings.provider
        settings.setKey("keep-key", for: provider)
        AppSettings.flushKeySave()
        let before = settings.autoOCR
        let snapshot = ProbeSettingsSnapshot(provider: settings.provider,
                                             connections: settings.connections,
                                             profiles: settings.profiles,
                                             voice: settings.voice,
                                             memory: settings.memory,
                                             briefing: settings.briefing,
                                             music: settings.music,
                                             research: settings.research,
                                             language: settings.language,
                                             appearance: settings.appearance,
                                             autoOCR: !before,
                                             vault: nil)
        ProbeSettingsGuard.restore(snapshot, to: settings)
        XCTAssertEqual(settings.key(for: provider), "keep-key")
        XCTAssertEqual(settings.autoOCR, !before)
    }
}
