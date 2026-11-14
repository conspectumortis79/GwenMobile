import GwenMobileKit
import Foundation

struct ReadAloudRequest: Equatable, Sendable {
    var enabled: Bool

    var stepWords: String { enabled ? "on" : "off" }

    static func from(_ args: [String: Any]) -> ReadAloudRequest? {
        if let value = args["enabled"] as? Bool { return ReadAloudRequest(enabled: value) }
        if let value = args["enabled"] as? Int { return ReadAloudRequest(enabled: value != 0) }
        if let value = args["enabled"] as? String {
            switch value.trimmed.lowercased() {
            case "true", "on", "yes", "1": return ReadAloudRequest(enabled: true)
            case "false", "off", "no", "0": return ReadAloudRequest(enabled: false)
            default: return nil
            }
        }
        return nil
    }
}
