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

struct DirectCapability: Equatable, Sendable {
    let entitled: Bool
    let available: Bool

    var isReady: Bool { entitled && available }

    static func of(infoKey: String, in bundle: Bundle, available: Bool) -> DirectCapability {
        DirectCapability(entitled: BuildFlag.isOn(infoKey, in: bundle), available: available)
    }

    #if DEBUG
    func trace(readyLabel: String) -> String {
        "berechtigt=\(entitled) mobilfunk_api=\(available) \(readyLabel)=\(isReady)"
    }
    #endif
}

enum DirectChannel {
    @MainActor
    static func select<Channel>(ready: Bool, direct: @MainActor () -> Channel?,
                                fallback: Channel,
                                combined: (Channel, Channel) -> Channel) -> Channel {
        guard ready, let primary = direct() else { return fallback }
        return combined(primary, fallback)
    }
}
