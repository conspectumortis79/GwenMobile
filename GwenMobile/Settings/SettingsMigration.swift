import GwenMobileKit
import Foundation

struct MigratedSettings: Equatable {
    var provider: ProviderID
    var connections: ProviderConnections
    var profiles: [ProviderID: ProviderProfile]
}

enum SettingsMigration {
    static func needed(in defaults: UserDefaults) -> Bool {
        defaults.string(forKey: SettingsKey.provider) == nil
            && SettingsKey.legacyKeys.contains { defaults.object(forKey: $0) != nil }
    }

    static func migrate(from defaults: UserDefaults) -> MigratedSettings {
        var connections = ProviderConnections()
        var provider = ProviderID.qwenCloud
        let legacyURL = defaults.string(forKey: SettingsKey.legacyBaseURL)?
            .trimmed ?? ""
        if !legacyURL.isEmpty {
            if let qwen = QwenEndpoints.config(matching: legacyURL) {
                connections.qwenCloud = qwen
            } else {
                provider = .openAICompatible
                connections.openAICompatible = OpenAICompatibleConfig(customURL: legacyURL)
            }
        }
        var profile = provider.descriptor.defaultProfile
        apply(defaults.string(forKey: SettingsKey.legacyChatModel), to: &profile.chatModel)
        apply(defaults.string(forKey: SettingsKey.legacyVisionModel), to: &profile.visionModel)
        apply(defaults.string(forKey: SettingsKey.legacyImageModel), to: &profile.imageModel)
        profile.availableModels = defaults.stringArray(forKey: SettingsKey.legacyAvailableModels) ?? []
        if let raw = defaults.string(forKey: SettingsKey.legacyChatThinkingLevel),
           let level = ThinkingLevel(rawValue: raw) {
            profile.chatThinkingLevel = level
        }
        if let data = defaults.data(forKey: SettingsKey.legacyModelCaps),
           let caps = try? JSONDecoder().decode([String: ModelCapabilities].self, from: data) {
            profile.modelCaps = caps
        }
        if profile.visionModel.isEmpty {
            profile.visionModel = ModelFilter.visionCandidates(profile.availableModels,
                                                               caps: profile.modelCaps).first ?? ""
        }
        if profile.imageModel.isEmpty {
            profile.imageModel = ModelFilter.imageCandidates(profile.availableModels).first ?? ""
        }
        if profile.videoModel.isEmpty {
            profile.videoModel = ModelFilter.videoCandidates(profile.availableModels,
                                                             caps: profile.modelCaps).first ?? ""
        }
        if profile.videoGenerationModels.isEmpty {
            profile.videoGenerationModels = ModelFilter.videoGenerationCandidates(profile.availableModels)
        }
        if profile.videoGenerationModel.isEmpty {
            profile.videoGenerationModel = profile.videoGenerationModels.first ?? ""
        }
        return MigratedSettings(provider: provider, connections: connections, profiles: [provider: profile])
    }

    static func removeLegacyKeys(from defaults: UserDefaults) {
        SettingsKey.legacyKeys.forEach { defaults.removeObject(forKey: $0) }
    }

    private static func apply(_ stored: String?, to target: inout String) {
        guard let stored, !stored.isEmpty else { return }
        target = stored
    }
}
