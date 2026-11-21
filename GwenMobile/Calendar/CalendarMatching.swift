import GwenMobileKit
import Foundation

typealias CalendarMatch = DatedMatchItem

extension CalendarMatch {
    init(title: String, location: String, notes: String, start: Date) {
        self.init(title: title, location: location, notes: notes, matchDate: start)
    }
}

enum CalendarMatching {
    static func bestIndex(in candidates: [CalendarMatch], query: String, now: Date,
                          requiresTitle: Bool = false) -> Int? {
        MatchScoring.bestIndex(in: candidates, query: query, now: now, requiresTitle: requiresTitle)
    }
}
