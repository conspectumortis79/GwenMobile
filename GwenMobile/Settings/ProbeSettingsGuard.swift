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
        let changed = drift(snapshot, settings)
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
        if !changed.isEmpty { flowLog.error("PROBE einstellungen zurueckgesetzt \(changed)") }
    }

    private static func drift(_ snapshot: ProbeSettingsSnapshot, _ settings: AppSettings) -> String {
        var parts: [String] = []
        if settings.provider != snapshot.provider {
            parts.append("anbieter=\(settings.provider.rawValue)->\(snapshot.provider.rawValue)")
        }
        let current = settings.profiles.sorted { $0.key.rawValue < $1.key.rawValue }
        for (id, profile) in current {
            guard let before = snapshot.profiles[id] else {
                parts.append("\(id.rawValue)=entfernt")
                continue
            }
            let slots = [("chat", profile.chatModel, before.chatModel),
                         ("vision", profile.visionModel, before.visionModel),
                         ("bild", profile.imageModel, before.imageModel),
                         ("video", profile.videoModel, before.videoModel),
                         ("videogenerierung", profile.videoGenerationModel, before.videoGenerationModel)]
            for (name, now, original) in slots where now != original {
                parts.append("\(id.rawValue)_\(name)=\(slot(now))->\(slot(original))")
            }
        }
        return parts.joined(separator: " ")
    }

    private static func slot(_ value: String) -> String {
        value.isEmpty ? "-" : value
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
