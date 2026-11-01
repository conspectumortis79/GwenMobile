import GwenMobileKit
import Foundation

enum ProfileStorage {
    static func decode(_ data: Data?) -> [ProviderID: ProviderProfile] {
        guard let data else { return [:] }
        if let keyed = try? JSONDecoder().decode([ProviderID: ProviderProfile].self, from: data) {
            return keyed
        }
        return legacyPairs(from: data)
    }

    private static func legacyPairs(from data: Data) -> [ProviderID: ProviderProfile] {
        guard let items = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [:] }
        var profiles: [ProviderID: ProviderProfile] = [:]
        for index in stride(from: 0, to: items.count - 1, by: 2) {
            guard let raw = items[index] as? String, let id = ProviderID(rawValue: raw),
                  let object = try? JSONSerialization.data(withJSONObject: items[index + 1]),
                  let profile = try? JSONDecoder().decode(ProviderProfile.self, from: object) else { continue }
            profiles[id] = profile
        }
        return profiles
    }
}
