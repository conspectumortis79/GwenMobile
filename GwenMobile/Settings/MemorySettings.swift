import Foundation

struct MemorySettings: Equatable, Codable {
    var enabled = true
    var suggestions = true
    var chips = true
    var retention: MemoryRetention = .forever

    var offersSuggestions: Bool { enabled && suggestions }

    static func load(from defaults: UserDefaults = .standard) -> MemorySettings {
        let d = defaults
        var settings = MemorySettings()
        settings.enabled = d.object(forKey: SettingsKey.memoryEnabled) as? Bool ?? true
        settings.suggestions = d.object(forKey: SettingsKey.memorySuggestions) as? Bool ?? true
        settings.chips = d.object(forKey: SettingsKey.memoryChips) as? Bool ?? true
        settings.retention = MemoryRetention(rawValue: d.string(forKey: SettingsKey.memoryRetention) ?? "")
            ?? .forever
        return settings
    }

    func store(to defaults: UserDefaults = .standard) {
        let d = defaults
        d.set(enabled, forKey: SettingsKey.memoryEnabled)
        d.set(suggestions, forKey: SettingsKey.memorySuggestions)
        d.set(chips, forKey: SettingsKey.memoryChips)
        d.set(retention.rawValue, forKey: SettingsKey.memoryRetention)
    }
}
