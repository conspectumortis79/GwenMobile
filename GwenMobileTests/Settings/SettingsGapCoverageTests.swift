@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import XCTest
import GwenMobileKit

@MainActor
final class SettingsGapCoverageTests: GwenTestCase {
    private let defaults = UserDefaults.standard

    private let touched = [
        SettingsKey.memoryEnabled, SettingsKey.memorySuggestions, SettingsKey.memoryChips,
        SettingsKey.memoryRetention, SettingsKey.musicService, SettingsKey.spotifyClientID,
        SettingsKey.outputVoice, SettingsKey.legacyTTSVoice, SettingsKey.speakAnswers, SettingsKey.listenMode,
        SettingsKey.conversationMode,
        SettingsKey.wakeWord, SettingsKey.stopWord, SettingsKey.cancelWord, SettingsKey.newChatWord,
        SettingsKey.listenOffWord, SettingsKey.deleteHistoryWord, SettingsKey.sentSound,
        SettingsKey.dictationLimit, SettingsKey.dictationSilence, SettingsKey.briefingEnabled,
        SettingsKey.briefingMinutes, SettingsKey.briefingWeather, SettingsKey.briefingReminders,
        SettingsKey.briefingBirthdays, SettingsKey.briefingTravel,
    ]

    private func snapshotDefaults() -> ([String: Any], Set<String>) {
        var saved: [String: Any] = [:]
        var present: Set<String> = []
        for key in touched where defaults.object(forKey: key) != nil {
            saved[key] = defaults.object(forKey: key)
            present.insert(key)
        }
        return (saved, present)
    }

    private func restoreDefaults(_ snapshot: ([String: Any], Set<String>)) {
        for key in touched {
            if snapshot.1.contains(key) {
                defaults.set(snapshot.0[key], forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    func testTheMemorySettingsDefaultsAndTheRoundTrip() {
        let snapshot = snapshotDefaults()
        defer { restoreDefaults(snapshot) }
        for key in [SettingsKey.memoryEnabled, SettingsKey.memorySuggestions,
                    SettingsKey.memoryChips, SettingsKey.memoryRetention] {
            defaults.removeObject(forKey: key)
        }
        let loaded = MemorySettings.load()
        XCTAssertTrue(loaded.enabled)
        XCTAssertTrue(loaded.suggestions)
        XCTAssertTrue(loaded.chips)
        XCTAssertEqual(loaded.retention, .forever)
        let stored = MemorySettings(enabled: false, suggestions: false, chips: false, retention: .twelveMonths)
        stored.store()
        XCTAssertEqual(MemorySettings.load(), stored)
    }

    func testTheMusicSettingsRoundTrip() {
        let snapshot = snapshotDefaults()
        defer { restoreDefaults(snapshot) }
        var settings = MusicSettings()
        settings.service = .spotify
        settings.spotifyClientID = "gap-client"
        settings.store()
        XCTAssertEqual(MusicSettings.load().service, .spotify)
        XCTAssertEqual(MusicSettings.load().spotifyClientID, "gap-client")
    }

    func testTheLegacyVoiceIsWrittenIntoTheNewKeyAtLaunch() {
        let snapshot = snapshotDefaults()
        defer { restoreDefaults(snapshot) }
        defaults.removeObject(forKey: SettingsKey.outputVoice)
        defaults.set("alte-stimme", forKey: SettingsKey.legacyTTSVoice)
        _ = AppSettings(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: SettingsKey.outputVoice), "alte-stimme")
        XCTAssertNil(defaults.object(forKey: SettingsKey.legacyTTSVoice))
    }

    func testTheVoiceSettingsDefaultsLegacyVoiceAndRoundTrip() {
        let snapshot = snapshotDefaults()
        defer { restoreDefaults(snapshot) }
        for key in [SettingsKey.outputVoice, SettingsKey.legacyTTSVoice, SettingsKey.wakeWord,
                    SettingsKey.stopWord, SettingsKey.cancelWord, SettingsKey.newChatWord,
                    SettingsKey.listenOffWord, SettingsKey.deleteHistoryWord,
                    SettingsKey.sentSound, SettingsKey.conversationMode] {
            defaults.removeObject(forKey: key)
        }
        let plain = VoiceSettings.load()
        XCTAssertEqual(plain.outputVoice, VoiceOption.systemDefaultID)
        XCTAssertEqual(plain.wakeWord, "")
        XCTAssertFalse(plain.conversationMode)
        defaults.set("alte-stimme", forKey: SettingsKey.legacyTTSVoice)
        XCTAssertEqual(VoiceSettings.load().outputVoice, "alte-stimme")
        defaults.set("neue-stimme", forKey: SettingsKey.outputVoice)
        XCTAssertEqual(VoiceSettings.load().outputVoice, "neue-stimme")
        var settings = VoiceSettings()
        settings.speakAnswers = true
        settings.listenMode = true
        settings.conversationMode = true
        settings.wakeWord = "hallo"
        settings.stopWord = "stopp"
        settings.cancelWord = "abbrechen"
        settings.newChatWord = "neu"
        settings.listenOffWord = "ruhe"
        settings.deleteHistoryWord = "loeschen"
        settings.sentSound = "pop"
        settings.dictationLimitSeconds = AppSettings.dictationLimitChoices.last
            ?? AppSettings.defaultDictationLimit
        settings.dictationSilenceSeconds = AppSettings.dictationSilenceChoices.last
            ?? AppSettings.defaultDictationSilence
        settings.store()
        XCTAssertEqual(VoiceSettings.load(), settings)
    }

    func testTheBriefingSettingsTimeDefaultsAndRoundTrip() {
        let snapshot = snapshotDefaults()
        defer { restoreDefaults(snapshot) }
        for key in [SettingsKey.briefingEnabled, SettingsKey.briefingMinutes, SettingsKey.briefingWeather,
                    SettingsKey.briefingReminders, SettingsKey.briefingBirthdays, SettingsKey.briefingTravel] {
            defaults.removeObject(forKey: key)
        }
        let plain = BriefingSettings.load()
        XCTAssertFalse(plain.enabled)
        XCTAssertEqual(plain.minutes, AppSettings.defaultBriefingMinutes)
        XCTAssertTrue(plain.weather)
        XCTAssertTrue(plain.reminders)
        XCTAssertTrue(plain.birthdays)
        XCTAssertTrue(plain.travel)
        var settings = BriefingSettings()
        var components = DateComponents()
        components.hour = 6
        components.minute = 45
        settings.time = Calendar.current.date(from: components) ?? Date()
        XCTAssertEqual(settings.minutes, 6 * 60 + 45)
        XCTAssertEqual(Calendar.current.component(.hour, from: settings.time), 6)
        XCTAssertEqual(Calendar.current.component(.minute, from: settings.time), 45)
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        let springNow = berlin.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 6)) ?? Date()
        let spring = settings.time(in: berlin, now: springNow)
        XCTAssertEqual(berlin.component(.hour, from: spring), 6)
        XCTAssertEqual(berlin.component(.minute, from: spring), 45)
        let autumnNow = berlin.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 6)) ?? Date()
        let autumn = settings.time(in: berlin, now: autumnNow)
        XCTAssertEqual(berlin.component(.hour, from: autumn), 6)
        XCTAssertEqual(berlin.component(.minute, from: autumn), 45)
        XCTAssertEqual(BriefingSettings.minutes(of: spring, in: berlin), 6 * 60 + 45)
        settings.enabled = true
        settings.weather = false
        settings.store()
        XCTAssertTrue(BriefingSettings.load().enabled)
        XCTAssertFalse(BriefingSettings.load().weather)
    }

    func testTheMigrationWithoutALegacyURL() {
        let suite = "settings-gap-\(UUID().uuidString)"
        let local = UserDefaults(suiteName: suite) ?? .standard
        defer { local.removePersistentDomain(forName: suite) }
        let migrated = SettingsMigration.migrate(from: local)
        XCTAssertEqual(migrated.provider, .qwenCloud)
        XCTAssertEqual(migrated.connections, ProviderConnections())
    }

    func testTheKeyAccessorsAndThePersistenceHelpers() {
        let settings = AppSettings.shared
        let provider = settings.provider
        let original = settings.key(for: provider)
        settings.apiKey = "sk-gap"
        XCTAssertEqual(settings.apiKey, "sk-gap")
        settings.clearKey(for: provider)
        XCTAssertEqual(settings.key(for: provider), "")
        XCTAssertNil(AppSettings.decode(Int.self, nil))
        settings.store(Double.infinity, forKey: "gap-not-stored")
        XCTAssertNil(defaults.data(forKey: "gap-not-stored"))
        AppSettings.scheduleKeySave(for: .qwenCloud)
        AppSettings.scheduleKeySave(for: .openRouter)
        AppSettings.flushKeySave()
        settings.reloadBlockedKeys()
        settings.setKey(original, for: provider)
        AppSettings.flushKeySave()
    }

    func testTheSettingsObserversStoreAndNormalize() {
        let snapshot = snapshotDefaults()
        defer { restoreDefaults(snapshot) }
        let settings = AppSettings.shared
        let profiles = settings.profiles
        settings.profiles = profiles
        let music = settings.music
        var changedMusic = music
        changedMusic.spotifyClientID = "observer-gap"
        settings.music = changedMusic
        XCTAssertEqual(defaults.string(forKey: SettingsKey.spotifyClientID), "observer-gap")
        settings.music = music
        let briefing = settings.briefing
        var changedBriefing = briefing
        changedBriefing.minutes = 9_999
        settings.briefing = changedBriefing
        XCTAssertLessThanOrEqual(settings.briefing.minutes, 23 * 60 + 59)
        settings.briefing = briefing
        let language = settings.language
        let voice = settings.voice
        settings.language = language == .de ? .en : .de
        settings.language = language
        settings.voice = voice
    }

    func testTheProviderSeedImport() throws {
        let settings = AppSettings.shared
        let paths = StoragePaths()
        let originalProvider = settings.provider
        let originalConnections = settings.connections
        try FileManager.default.createDirectory(at: paths.documents, withIntermediateDirectories: true)
        let json = #"{"provider":"openrouter","keys":{"openrouter":"sk-seed"}}"#
        try Data(json.utf8).write(to: paths.providerSeed)
        settings.importProviderSeed()
        XCTAssertEqual(settings.provider, .openRouter)
        XCTAssertEqual(settings.key(for: .openRouter), "sk-seed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.providerSeed.path))
        settings.provider = originalProvider
        settings.connections = originalConnections
    }

    func testTheKeySeedImport() throws {
        let settings = AppSettings.shared
        let paths = StoragePaths()
        let original = settings.key(for: .qwenCloud)
        settings.clearKey(for: .qwenCloud)
        AppSettings.flushKeySave()
        try FileManager.default.createDirectory(at: paths.documents, withIntermediateDirectories: true)
        try Data("  sk-from-file  \n".utf8).write(to: paths.apiKeySeed)
        settings.importSeedFile()
        XCTAssertEqual(settings.key(for: .qwenCloud), "sk-from-file")
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.apiKeySeed.path))
        settings.setKey(original, for: .qwenCloud)
        AppSettings.flushKeySave()
    }

    func testTheCountLabels() {
        XCTAssertEqual(SettingsView.priceWatchCountLabel(1), L.t("price_watch_count_one"))
        XCTAssertEqual(SettingsView.priceWatchCountLabel(3), L.n("price_watch_count_many", 3))
        XCTAssertEqual(SettingsView.memoryCountLabel(1), L.t("memory_count_one"))
        XCTAssertEqual(SettingsView.memoryCountLabel(4), L.n("memory_count_many", 4))
    }

    func testTheDictationRowsDrawEveryChoice() async throws {
        let view = SettingsView()
        let controller = mountView(Form {
            view.dictationLimitRow
            view.dictationSilenceRow
        }, size: CGSize(width: 390, height: 700))
        try await settleHosted(controller, milliseconds: 300)
        XCTAssertNotNil(controller.view.window)
        XCTAssertFalse(AppSettings.dictationLimitChoices.isEmpty)
        XCTAssertFalse(AppSettings.dictationSilenceChoices.isEmpty)
    }
}
