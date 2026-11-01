import GwenMobileKit
import Foundation

struct ConnectionIdentity: Equatable {
    var provider: ProviderID
    var baseURL: String
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    nonisolated static let dictationLimitChoices = [60, 120, 180, 300]
    nonisolated static let dictationSilenceChoices = [2, 3, 4, 5, 6, 8, 10]
    nonisolated static let defaultDictationLimit = 180
    nonisolated static let defaultDictationSilence = 4
    nonisolated static let defaultBriefingMinutes = 7 * 60 + 30

    nonisolated static func validChoice(_ value: Int?, choices: [Int], fallback: Int) -> Int {
        guard let value, choices.contains(value) else { return fallback }
        return value
    }

    let d: UserDefaults
    var vault: ProviderKeyVault
    var probing: Set<ProviderID> = []
    static var pendingKeySave: (provider: ProviderID, task: Task<Void, Never>)?

    @Published var provider: ProviderID {
        didSet {
            d.set(provider.rawValue, forKey: SettingsKey.provider)
            connectionChanged()
        }
    }
    @Published var connections: ProviderConnections {
        didSet {
            store(connections, forKey: SettingsKey.providerConnections)
            connectionChanged()
        }
    }
    @Published var profiles: [ProviderID: ProviderProfile] {
        didSet { store(profiles, forKey: SettingsKey.providerProfiles) }
    }
    @Published var keychainProblem: String?
    @Published var voice: VoiceSettings {
        didSet {
            let fixed = voice.normalized
            if fixed != voice {
                voice = fixed
                return
            }
            voice.store(to: d)
        }
    }
    @Published var memory: MemorySettings {
        didSet { memory.store(to: d) }
    }
    @Published var briefing: BriefingSettings {
        didSet {
            let fixed = briefing.normalized
            if fixed != briefing {
                briefing = fixed
                return
            }
            briefing.store(to: d)
        }
    }
    @Published var music: MusicSettings {
        didSet { music.store(to: d) }
    }
    @Published var research: ResearchSettings {
        didSet { research.store(to: d) }
    }
    @Published var language: AppLanguage {
        didSet {
            d.set(language.rawValue, forKey: SettingsKey.language)
            L.apply(language)
            if language != oldValue, !VoiceCatalog.isPersonalVoice(identifier: voice.outputVoice) {
                voice.outputVoice = VoiceOption.systemDefaultID
            }
        }
    }
    @Published var appearance: AppAppearance {
        didSet { d.set(appearance.rawValue, forKey: SettingsKey.appearance) }
    }
    @Published var autoOCR: Bool { didSet { d.set(autoOCR, forKey: SettingsKey.autoOCR) } }

    init(keyStore: any KeyStoring = KeychainKeyStore(), defaults: UserDefaults = .standard) {
        d = defaults
        self.vault = ProviderKeyVault(store: keyStore)
        L.apply(L.persistedLanguage(defaults: defaults))
        language = L.lang
        appearance = AppAppearance.persisted(defaults: defaults)
        autoOCR = d.object(forKey: SettingsKey.autoOCR) as? Bool ?? true
        voice = .load(from: defaults)
        memory = .load(from: defaults)
        briefing = .load(from: defaults)
        music = .load(from: defaults)
        research = .load(from: defaults)
        let migrating = SettingsMigration.needed(in: d)
        if migrating {
            let migrated = SettingsMigration.migrate(from: d)
            provider = migrated.provider
            connections = migrated.connections
            profiles = migrated.profiles
        } else {
            provider = ProviderID(rawValue: d.string(forKey: SettingsKey.provider) ?? "") ?? .qwenCloud
            connections = Self.decode(ProviderConnections.self, d.data(forKey: SettingsKey.providerConnections))
                ?? ProviderConnections()
            profiles = ProfileStorage.decode(d.data(forKey: SettingsKey.providerProfiles))
        }
        if migrating {
            d.set(provider.rawValue, forKey: SettingsKey.provider)
            store(connections, forKey: SettingsKey.providerConnections)
            store(profiles, forKey: SettingsKey.providerProfiles)
        }
        SettingsMigration.removeLegacyKeys(from: d)
        voice.store(to: d)
        if vault.hasBlockedEntry { keychainProblem = L.t("keychain_blocked") }
        #if DEBUG
        importSeedFile()
        importProviderSeed()
        #endif
        connectionChanged()
    }
}
