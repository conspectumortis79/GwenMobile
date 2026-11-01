@testable import GwenMobileFeatureCore
@testable import GwenMobileDevice
import GwenMobileKit
import XCTest

@MainActor
final class SettingsMigrationAppSettingsTests: GwenTestCase {
    func testGroupedSettingsUseTheInjectedDefaults() throws {
        let suite = "gwen-settings-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: SettingsKey.speakAnswers)
        defaults.set(MemoryRetention.twelveMonths.rawValue, forKey: SettingsKey.memoryRetention)
        defaults.set(MusicService.spotify.rawValue, forKey: SettingsKey.musicService)
        defaults.set(true, forKey: SettingsKey.researchVerifySources)
        defaults.set(true, forKey: SettingsKey.briefingEnabled)
        defaults.set(6 * 60 + 15, forKey: SettingsKey.briefingMinutes)
        defaults.set(AppLanguage.fr.rawValue, forKey: SettingsKey.language)
        defaults.set(AppAppearance.dark.rawValue, forKey: SettingsKey.appearance)
        let settings = AppSettings(keyStore: MemoryKeyStore(), defaults: defaults)
        XCTAssertTrue(settings.voice.speakAnswers)
        XCTAssertEqual(settings.memory.retention, .twelveMonths)
        XCTAssertEqual(settings.music.service, .spotify)
        XCTAssertTrue(settings.research.verifySources)
        XCTAssertTrue(settings.briefing.enabled)
        XCTAssertEqual(settings.briefing.minutes, 6 * 60 + 15)
        XCTAssertEqual(settings.language, .fr)
        XCTAssertEqual(settings.appearance, .dark)
        settings.voice.speakAnswers = false
        XCTAssertEqual(defaults.object(forKey: SettingsKey.speakAnswers) as? Bool, false)
    }

    func testTheLegacySettingsAreMigratedAtLaunch() throws {
        let suite = "gwen-migration-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        defaults.set("https://legacy.example.test/v1", forKey: SettingsKey.legacyBaseURL)
        defaults.set("legacy-chat-model", forKey: SettingsKey.legacyChatModel)
        defaults.set(["legacy-model"], forKey: SettingsKey.legacyAvailableModels)
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.provider, .openAICompatible)
        XCTAssertEqual(settings.profiles[settings.provider]?.chatModel, "legacy-chat-model")
        XCTAssertEqual(settings.profiles[settings.provider]?.availableModels, ["legacy-model"])
        XCTAssertNil(defaults.string(forKey: SettingsKey.legacyBaseURL))
        XCTAssertNotNil(defaults.string(forKey: SettingsKey.provider))
    }

    func testForgettingADeletedModelClearsEveryReference() throws {
        let suite = "gwen-forget-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(keyStore: MemoryKeyStore(), defaults: defaults)
        settings.updateProfile(of: .local) { profile in
            profile.chatModel = "qwen"
            profile.visionModel = "gemma"
            profile.imageModel = "gemma"
            profile.availableModels = ["qwen", "gemma"]
            profile.imageModels = ["gemma"]
            profile.modelCaps["gemma"] = ModelCapabilities(thinking: .unknown, vision: .rejected)
        }
        settings.forgetDeletedModel("gemma", of: .local)
        let profile = settings.profile(of: .local)
        XCTAssertEqual(profile.chatModel, "qwen")
        XCTAssertEqual(profile.visionModel, "")
        XCTAssertEqual(profile.imageModel, "")
        XCTAssertEqual(profile.availableModels, ["qwen"])
        XCTAssertEqual(profile.imageModels, [])
        XCTAssertNil(profile.modelCaps["gemma"])
        settings.forgetDeletedModel("qwen", of: .local)
        XCTAssertEqual(settings.profile(of: .local).chatModel, "")
    }
}
