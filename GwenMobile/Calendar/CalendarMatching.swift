import GwenMobileKit
import Foundation

struct CalendarMatch: Equatable, Sendable {
    var title: String
    var location: String
    var notes: String
    var start: Date

    var titleHaystack: String { MatchText.title(title) }
    var detailHaystack: String { MatchText.detail(location, notes) }
}

extension CalendarMatch: MatchCandidate {
    var matchDate: Date? { start }
}

enum CalendarMatching {
    static func bestIndex(in candidates: [CalendarMatch], query: String, now: Date,
                          requiresTitle: Bool = false) -> Int? {
        MatchScoring.bestIndex(in: candidates, query: query, now: now, requiresTitle: requiresTitle)
    }
}
