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
    private static let decoration = CharacterSet(charactersIn: " \n\t-*\u{2022}>\u{201C}\u{201D}\"`\u{201E}\u{201A}")
    private static let tokens = [SearchMarker.token, ChartMarker.token]

    static func parse(_ text: String) -> RouteDecision {
        var decision = RouteDecision()
        consume(text) { token in
            if token == SearchMarker.token { decision.search = true } else { decision.chart = true }
        }
        return decision
    }

    static func strip(_ text: String) -> String {
        consume(text) { _ in }
    }

    @discardableResult
    private static func consume(_ text: String, didConsume: (String) -> Void) -> String {
        var rest = text.trimmingCharacters(in: decoration)
        var consumed = true
        while consumed {
            consumed = false
            for token in tokens where rest.hasPrefix(token) {
                didConsume(token)
                rest = remainder(after: token, in: rest)
                consumed = true
            }
        }
        return rest
    }

    private static func remainder(after token: String, in text: String) -> String {
        String(text.dropFirst(token.count)).trimmingCharacters(in: decoration)
    }
}
