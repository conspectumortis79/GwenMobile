import Foundation

struct ResearchSettings: Equatable, Codable {
    var verifySources = false

    static func load(from defaults: UserDefaults = .standard) -> ResearchSettings {
        var settings = ResearchSettings()
        settings.verifySources = SettingsDefaults.bool(defaults, SettingsKey.researchVerifySources, false)
        return settings
    }

    func store(to defaults: UserDefaults = .standard) {
        defaults.set(verifySources, forKey: SettingsKey.researchVerifySources)
    }
}
