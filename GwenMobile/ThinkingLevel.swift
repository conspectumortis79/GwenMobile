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

enum ThinkingDirective: Equatable, Sendable {
    case nothing
    case effort(ThinkingLevel)
    case suppressThinking

    var bodyEntries: [String: Any] {
        switch self {
        case .nothing: return [:]
        case .effort(let level): return ["reasoning_effort": level.rawValue]
        case .suppressThinking: return ["enable_thinking": false]
        }
    }

    var sendsAnything: Bool { !bodyEntries.isEmpty }

    func applied(to body: inout [String: Any]) {
        body.merge(bodyEntries) { _, new in new }
    }
}

struct ThinkingCapabilities: Codable, Equatable, Sendable {
    var levels: [ThinkingLevel] = []
    var canSwitchOff = false

    static let unknown = ThinkingCapabilities()

    var isKnown: Bool { !levels.isEmpty || canSwitchOff }

    var offeredLevels: [ThinkingLevel] {
        ThinkingLevel.allCases.filter { supports($0) }
    }

    func supports(_ level: ThinkingLevel) -> Bool {
        level == .modelDefault || directive(for: level).sendsAnything
    }

    func directive(for level: ThinkingLevel) -> ThinkingDirective {
        switch level {
        case .modelDefault:
            return .nothing
        case .off:
            if levels.contains(.off) { return .effort(.off) }
            return canSwitchOff ? .suppressThinking : .nothing
        default:
            return levels.contains(level) || level.isCore ? .effort(level) : .nothing
        }
    }
}
