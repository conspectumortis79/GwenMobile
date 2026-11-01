enum DayChoice: String, CaseIterable, Equatable, Sendable {
    case today
    case tomorrow
    case dayAfter

    var index: Int {
        switch self {
        case .today: return 0
        case .tomorrow: return 1
        case .dayAfter: return 2
        }
    }

    var offset: Int { index }

    static func at(index: Int) -> DayChoice {
        switch index {
        case 0: return .today
        case 2: return .dayAfter
        default: return .tomorrow
        }
    }

    static func parse(_ raw: String?) -> DayChoice {
        switch (raw ?? "").lowercased() {
        case "today": return .today
        case "dayafter": return .dayAfter
        default: return .tomorrow
        }
    }
}
