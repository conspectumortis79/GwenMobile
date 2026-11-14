import Foundation

struct MusicSettings: Equatable, Codable {
    var service: MusicService = .appleMusic
    var spotifyClientID = ""

    static func load(from defaults: UserDefaults = .standard) -> MusicSettings {
        let d = defaults
        var settings = MusicSettings()
        settings.service = MusicService(rawValue: d.string(forKey: SettingsKey.musicService) ?? "") ?? .appleMusic
        settings.spotifyClientID = d.string(forKey: SettingsKey.spotifyClientID) ?? ""
        return settings
    }

    func store(to defaults: UserDefaults = .standard) {
        let d = defaults
        d.set(service.rawValue, forKey: SettingsKey.musicService)
        d.set(spotifyClientID, forKey: SettingsKey.spotifyClientID)
    }
}
