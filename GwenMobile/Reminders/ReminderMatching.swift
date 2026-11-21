import GwenMobileKit
import Foundation

typealias ReminderMatch = DatedMatchItem

extension ReminderMatch {
    init(title: String, location: String, notes: String, due: Date?) {
        self.init(title: title, location: location, notes: notes, matchDate: due)
    }
}

enum ReminderMatching {
    static func bestIndex(in candidates: [ReminderMatch], query: String, now: Date,
                          requiresTitle: Bool = true) -> Int? {
        MatchScoring.bestIndex(in: candidates, query: query, now: now, requiresTitle: requiresTitle)
    }
}
