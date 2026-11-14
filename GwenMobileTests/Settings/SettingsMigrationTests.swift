@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class SettingsMigrationTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = "migration-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testFreshInstallNeedsNoMigration() {
        XCTAssertFalse(SettingsMigration.needed(in: defaults))
    }

    func testAlreadyMigratedDefaultsAreLeftAlone() {
        defaults.set("qwen", forKey: SettingsKey.provider)
        defaults.set("https://api.openai.com/v1", forKey: SettingsKey.legacyBaseURL)
        XCTAssertFalse(SettingsMigration.needed(in: defaults))
    }

    func testLegacyQwenEndpointBecomesBillingRegionAndProfile() {
        defaults.set("https://dashscope-us.aliyuncs.com/compatible-mode/v1", forKey: SettingsKey.legacyBaseURL)
        defaults.set("qwen3.8-max", forKey: SettingsKey.legacyChatModel)
        defaults.set(["qwen3.8-max", "wan2.7-image"], forKey: SettingsKey.legacyAvailableModels)
        defaults.set("high", forKey: SettingsKey.legacyChatThinkingLevel)
        let caps = ["qwen3.8-max": ModelCapabilities(thinking: .unknown, vision: .supported)]
        defaults.set(try? JSONEncoder().encode(caps), forKey: SettingsKey.legacyModelCaps)
        XCTAssertTrue(SettingsMigration.needed(in: defaults))

        let migrated = SettingsMigration.migrate(from: defaults)
        XCTAssertEqual(migrated.provider, .qwenCloud)
        XCTAssertEqual(migrated.connections.qwenCloud, QwenCloudConfig(billing: .payAsYouGo, region: .us))
        let profile = migrated.profiles[.qwenCloud]
        XCTAssertEqual(profile?.chatModel, "qwen3.8-max")
        XCTAssertEqual(profile?.visionModel, "qwen3.8-max")
        XCTAssertEqual(profile?.imageModel, "wan2.7-image")
        XCTAssertEqual(profile?.availableModels, ["qwen3.8-max", "wan2.7-image"])
        XCTAssertEqual(profile?.chatThinkingLevel, .high)
        XCTAssertEqual(profile?.modelCaps, caps)
    }

    func testLegacyEuWorkspaceURLKeepsTheWorkspace() {
        defaults.set("https://llm-42.eu-central-1.maas.aliyuncs.com/compatible-mode/v1",
                     forKey: SettingsKey.legacyBaseURL)
        let migrated = SettingsMigration.migrate(from: defaults)
        XCTAssertEqual(migrated.connections.qwenCloud,
                       QwenCloudConfig(billing: .payAsYouGo, region: .eu, workspace: "llm-42"))
    }

    func testLegacyCustomURLMovesToTheOpenAICompatibleProvider() {
        defaults.set("https://my.server/v1", forKey: SettingsKey.legacyBaseURL)
        defaults.set("llama3", forKey: SettingsKey.legacyChatModel)
        let migrated = SettingsMigration.migrate(from: defaults)
        XCTAssertEqual(migrated.provider, .openAICompatible)
        XCTAssertEqual(migrated.connections.openAICompatible.baseURL, "https://my.server/v1")
        XCTAssertEqual(migrated.connections.openAICompatible.preset, "custom")
        XCTAssertEqual(migrated.profiles[.openAICompatible]?.chatModel, "llama3")
        XCTAssertNil(migrated.profiles[.qwenCloud])
    }

    func testEmptyLegacyValuesFallBackToTheProviderDefaults() {
        defaults.set("", forKey: SettingsKey.legacyBaseURL)
        defaults.set("", forKey: SettingsKey.legacyChatModel)
        defaults.set("kaputt", forKey: SettingsKey.legacyChatThinkingLevel)
        let migrated = SettingsMigration.migrate(from: defaults)
        XCTAssertEqual(migrated.provider, .qwenCloud)
        XCTAssertEqual(migrated.connections, ProviderConnections())
        XCTAssertEqual(migrated.profiles[.qwenCloud], QwenCloudDescriptor().defaultProfile)
    }

    func testLegacyKeysAreRemovedAfterwards() {
        for key in SettingsKey.legacyKeys { defaults.set("x", forKey: key) }
        SettingsMigration.removeLegacyKeys(from: defaults)
        for key in SettingsKey.legacyKeys { XCTAssertNil(defaults.object(forKey: key), key) }
    }
}
