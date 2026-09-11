import Foundation

enum SearchMarker {
    static let token = "[[SEARCH]]"
}

enum ChartMarker {
    static let token = "[[CHART]]"
}

struct RouteDecision: Equatable, Sendable {
    var search = false
    var chart = false

    var isEmpty: Bool { !search && !chart }
}

enum ChatMarkers {
    static func parse(_ text: String) -> RouteDecision {
        var rest = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var decision = RouteDecision()
        var consumed = true
        while consumed {
            consumed = false
            for token in [SearchMarker.token, ChartMarker.token] where rest.hasPrefix(token) {
                if token == SearchMarker.token { decision.search = true } else { decision.chart = true }
                rest = remainder(after: token, in: rest)
                consumed = true
            }
        }
        return decision
    }

    static func strip(_ text: String) -> String {
        var rest = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var changed = true
        while changed {
            changed = false
            for token in [SearchMarker.token, ChartMarker.token] where rest.hasPrefix(token) {
                rest = remainder(after: token, in: rest)
                changed = true
            }
        }
        return rest
    }

    private static func remainder(after token: String, in text: String) -> String {
        String(text.dropFirst(token.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
