import GwenMobileKit
import Foundation

enum ThinkingLevel: String, CaseIterable, Codable, Sendable {
    case modelDefault = "default"
    case off = "none"
    case minimal
    case low
    case medium
    case high
    case xhigh
    case max

    static let coreCases: [ThinkingLevel] = [.low, .medium, .high, .xhigh]

    var isCore: Bool { ThinkingLevel.coreCases.contains(self) }

    var labelKey: String {
        switch self {
        case .modelDefault: return "thinking_default"
        case .off: return "thinking_off"
        case .minimal: return "thinking_minimal"
        case .low: return "thinking_low"
        case .medium: return "thinking_medium"
        case .high: return "thinking_high"
        case .xhigh: return "thinking_xhigh"
        case .max: return "thinking_max"
        }
    }

    nonisolated var label: String { L.t(labelKey) }
}

enum ThinkingEncoding: String, Codable, Sendable {
    case dashScope
    case openAI
    case openRouter
}

struct ThinkingDirective: Equatable, Sendable {
    enum Intent: Equatable, Sendable {
        case nothing
        case effort(ThinkingLevel)
        case suppressThinking
    }

    var intent: Intent
    var encoding: ThinkingEncoding = .dashScope

    static let nothing = ThinkingDirective(intent: .nothing)

    static func effort(_ level: ThinkingLevel, _ encoding: ThinkingEncoding = .dashScope) -> ThinkingDirective {
        ThinkingDirective(intent: .effort(level), encoding: encoding)
    }

    static func suppressing(_ encoding: ThinkingEncoding) -> ThinkingDirective {
        ThinkingDirective(intent: .suppressThinking, encoding: encoding)
    }

    var bodyEntries: [String: Any] {
        switch (intent, encoding) {
        case (.nothing, _):
            return [:]
        case (.effort(let level), .openRouter):
            return ["reasoning": ["effort": level.rawValue]]
        case (.effort(let level), _):
            return ["reasoning_effort": level.rawValue]
        case (.suppressThinking, .dashScope):
            return ["enable_thinking": false]
        case (.suppressThinking, .openAI):
            return ["reasoning_effort": ThinkingLevel.off.rawValue]
        case (.suppressThinking, .openRouter):
            return ["reasoning": ["enabled": false]]
        }
    }

    var sendsAnything: Bool { intent != .nothing }

    func applied(to body: inout [String: Any]) {
        body.merge(bodyEntries) { _, new in new }
    }
}

struct ThinkingCapabilities: Codable, Equatable, Sendable {
    var levels: [ThinkingLevel] = []
    var canSwitchOff = false
    var encoding: ThinkingEncoding = .dashScope
    var probed = false

    static let unknown = ThinkingCapabilities()
    static let gatewayLevels: [ThinkingLevel] = [.off, .minimal, .low, .medium, .high, .xhigh, .max]

    init(levels: [ThinkingLevel] = [], canSwitchOff: Bool = false,
         encoding: ThinkingEncoding = .dashScope, probed: Bool = false) {
        self.levels = levels
        self.canSwitchOff = canSwitchOff
        self.encoding = encoding
        self.probed = probed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        levels = try container.decodeIfPresent([ThinkingLevel].self, forKey: .levels) ?? []
        canSwitchOff = try container.decodeIfPresent(Bool.self, forKey: .canSwitchOff) ?? false
        encoding = try container.decodeIfPresent(ThinkingEncoding.self, forKey: .encoding) ?? .dashScope
        probed = try container.decodeIfPresent(Bool.self, forKey: .probed) ?? false
    }

    var isKnown: Bool { probed || !levels.isEmpty || canSwitchOff }

    var offeredLevels: [ThinkingLevel] {
        ThinkingLevel.allCases.filter { supports($0) }
    }

    var offersControl: Bool { offeredLevels.count > 1 }

    func supports(_ level: ThinkingLevel) -> Bool {
        level == .modelDefault || directive(for: level).sendsAnything
    }

    func directive(for level: ThinkingLevel) -> ThinkingDirective {
        switch level {
        case .modelDefault:
            return .nothing
        case .off:
            if levels.contains(.off) { return .effort(.off, encoding) }
            return canSwitchOff ? .suppressing(encoding) : .nothing
        default:
            let confirmed = levels.contains(level) || (!probed && levels.isEmpty && level.isCore)
            return confirmed ? .effort(level, encoding) : .nothing
        }
    }
}
