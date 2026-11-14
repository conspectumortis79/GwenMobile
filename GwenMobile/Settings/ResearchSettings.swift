import Foundation

struct ResearchSettings: Equatable, Codable {
    var verifySources = false

    static func load(from defaults: UserDefaults = .standard) -> ResearchSettings {
        let d = defaults
        var settings = ResearchSettings()
        settings.verifySources = d.object(forKey: SettingsKey.researchVerifySources) as? Bool ?? false
        return settings
    }

    func store(to defaults: UserDefaults = .standard) {
        defaults.set(verifySources, forKey: SettingsKey.researchVerifySources)
    }
}
