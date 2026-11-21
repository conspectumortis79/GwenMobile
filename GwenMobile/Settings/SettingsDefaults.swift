import Foundation

enum SettingsDefaults {
    static func flag(_ defaults: UserDefaults, _ key: String) -> Bool {
        defaults.bool(forKey: key)
    }

    static func bool(_ defaults: UserDefaults, _ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }

    static func int(_ defaults: UserDefaults, _ key: String, _ fallback: Int) -> Int {
        defaults.object(forKey: key) as? Int ?? fallback
    }

    static func string(_ defaults: UserDefaults, _ key: String) -> String {
        defaults.string(forKey: key) ?? ""
    }

    static func storedString(_ defaults: UserDefaults, _ key: String) -> String? {
        defaults.string(forKey: key)
    }

    static func rawValue<Value: RawRepresentable>(_ defaults: UserDefaults, _ key: String,
                                                  _ fallback: Value) -> Value where Value.RawValue == String {
        Value(rawValue: string(defaults, key)) ?? fallback
    }

    static func rawValue<Value: RawRepresentable>(_ defaults: UserDefaults, _ key: String,
                                                  _ fallback: Value) -> Value where Value.RawValue == Int {
        Value(rawValue: int(defaults, key, fallback.rawValue)) ?? fallback
    }

    static func validChoice(_ defaults: UserDefaults, _ key: String, _ choices: [Int], _ fallback: Int) -> Int {
        AppSettings.validChoice(defaults.object(forKey: key) as? Int, choices: choices, fallback: fallback)
    }
}
