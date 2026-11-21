import Foundation

struct MusicSettings: Equatable, Codable {
    var service: MusicService = .appleMusic
    var spotifyClientID = ""

    static func load(from defaults: UserDefaults = .standard) -> MusicSettings {
        var settings = MusicSettings()
        settings.service = SettingsDefaults.rawValue(defaults, SettingsKey.musicService, .appleMusic)
        settings.spotifyClientID = SettingsDefaults.string(defaults, SettingsKey.spotifyClientID)
        return settings
    }

    func store(to defaults: UserDefaults = .standard) {
        defaults.set(service.rawValue, forKey: SettingsKey.musicService)
        defaults.set(spotifyClientID, forKey: SettingsKey.spotifyClientID)
    }
}
