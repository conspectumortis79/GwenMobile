import GwenMobileKit
import Foundation

struct ReminderMatch: Equatable, Sendable {
    var title: String
    var location: String
    var notes: String
    var due: Date?

    var titleHaystack: String { MatchText.title(title) }
    var detailHaystack: String { MatchText.detail(location, notes) }
}

extension ReminderMatch: MatchCandidate {
    var matchDate: Date? { due }
}

enum ReminderMatching {
    static func bestIndex(in candidates: [ReminderMatch], query: String, now: Date,
                          requiresTitle: Bool = true) -> Int? {
        MatchScoring.bestIndex(in: candidates, query: query, now: now, requiresTitle: requiresTitle)
    }
}
