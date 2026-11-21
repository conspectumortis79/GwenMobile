import Foundation

struct MemorySettings: Equatable, Codable {
    var enabled = true
    var suggestions = true
    var chips = true
    var retention: MemoryRetention = .forever

    var offersSuggestions: Bool { enabled && suggestions }

    static func load(from defaults: UserDefaults = .standard) -> MemorySettings {
        var settings = MemorySettings()
        settings.enabled = SettingsDefaults.bool(defaults, SettingsKey.memoryEnabled, true)
        settings.suggestions = SettingsDefaults.bool(defaults, SettingsKey.memorySuggestions, true)
        settings.chips = SettingsDefaults.bool(defaults, SettingsKey.memoryChips, true)
        settings.retention = SettingsDefaults.rawValue(defaults, SettingsKey.memoryRetention, .forever)
        return settings
    }

    func store(to defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: SettingsKey.memoryEnabled)
        defaults.set(suggestions, forKey: SettingsKey.memorySuggestions)
        defaults.set(chips, forKey: SettingsKey.memoryChips)
        defaults.set(retention.rawValue, forKey: SettingsKey.memoryRetention)
    }
}
