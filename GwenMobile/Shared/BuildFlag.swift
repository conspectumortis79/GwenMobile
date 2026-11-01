import GwenMobileKit
import Foundation

enum BuildFlag {
    static let affirmative: Set<String> = ["YES", "TRUE", "1"]

    static func isOn(_ flag: Any?) -> Bool {
        if let value = flag as? Bool { return value }
        guard let text = flag as? String else { return false }
        return affirmative.contains(text.trimmed.uppercased())
    }

    static func isOn(_ key: String, in bundle: Bundle) -> Bool {
        isOn(bundle.object(forInfoDictionaryKey: key))
    }
}
