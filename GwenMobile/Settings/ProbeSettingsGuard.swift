#if DEBUG
import GwenMobileKit
import Foundation

@MainActor
struct ProbeSettingsSnapshot {
    let provider: ProviderID
    let connections: ProviderConnections
    let profiles: [ProviderID: ProviderProfile]
    let voice: VoiceSettings
    let memory: MemorySettings
    let briefing: BriefingSettings
    let music: MusicSettings
    let research: ResearchSettings
    let language: AppLanguage
    let appearance: AppAppearance
    let autoOCR: Bool
}

@MainActor
enum ProbeSettingsGuard {
    private struct Backup: Codable {
        let provider: ProviderID
        let connections: ProviderConnections
        let profiles: [ProviderID: ProviderProfile]
        let voice: VoiceSettings?
        let memory: MemorySettings?
        let briefing: BriefingSettings?
        let music: MusicSettings?
        let research: ResearchSettings?
        let language: AppLanguage?
        let appearance: AppAppearance?
        let autoOCR: Bool?
        let probe: String
    }

    private static var backupURL: URL {
        StoragePaths().support.appendingPathComponent("probe-settings-backup.json")
    }

    static var keepProfiles = false

    static func begin(_ settings: AppSettings = .shared, probe: String) -> ProbeSettingsSnapshot {
        restorePendingIfNeeded(settings)
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
                                             autoOCR: settings.autoOCR)
        write(Backup(provider: snapshot.provider, connections: snapshot.connections,
                     profiles: snapshot.profiles, voice: snapshot.voice, memory: snapshot.memory,
                     briefing: snapshot.briefing, music: snapshot.music, research: snapshot.research,
                     language: snapshot.language, appearance: snapshot.appearance,
                     autoOCR: snapshot.autoOCR, probe: probe))
        return snapshot
    }

    static func restore(_ snapshot: ProbeSettingsSnapshot, to settings: AppSettings = .shared) {
        apply(snapshot, to: settings)
        clearBackup()
    }

    static func restorePendingIfNeeded(_ settings: AppSettings = .shared) {
        guard let data = try? Data(contentsOf: backupURL),
              let backup = try? JSONDecoder().decode(Backup.self, from: data) else { return }
        let snapshot = ProbeSettingsSnapshot(provider: backup.provider,
                                             connections: backup.connections,
                                             profiles: backup.profiles,
                                             voice: backup.voice ?? settings.voice,
                                             memory: backup.memory ?? settings.memory,
                                             briefing: backup.briefing ?? settings.briefing,
                                             music: backup.music ?? settings.music,
                                             research: backup.research ?? settings.research,
                                             language: backup.language ?? settings.language,
                                             appearance: backup.appearance ?? settings.appearance,
                                             autoOCR: backup.autoOCR ?? settings.autoOCR)
        apply(snapshot, to: settings)
        flowLog.error("PROBE einstellungen wiederhergestellt probe=\(backup.probe)")
        clearBackup()
    }

    private static func apply(_ snapshot: ProbeSettingsSnapshot, to settings: AppSettings) {
        if settings.provider != snapshot.provider { settings.provider = snapshot.provider }
        if settings.connections != snapshot.connections { settings.connections = snapshot.connections }
        if !keepProfiles, settings.profiles != snapshot.profiles { settings.profiles = snapshot.profiles }
        keepProfiles = false
        if settings.language != snapshot.language { settings.language = snapshot.language }
        if settings.voice != snapshot.voice { settings.voice = snapshot.voice }
        if settings.memory != snapshot.memory { settings.memory = snapshot.memory }
        if settings.briefing != snapshot.briefing { settings.briefing = snapshot.briefing }
        if settings.music != snapshot.music { settings.music = snapshot.music }
        if settings.research != snapshot.research { settings.research = snapshot.research }
        if settings.appearance != snapshot.appearance { settings.appearance = snapshot.appearance }
        if settings.autoOCR != snapshot.autoOCR { settings.autoOCR = snapshot.autoOCR }
    }

    private static func write(_ backup: Backup) {
        guard let data = try? JSONEncoder().encode(backup) else { return }
        let url = backupURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private static func clearBackup() {
        try? FileManager.default.removeItem(at: backupURL)
    }
}
#endif
