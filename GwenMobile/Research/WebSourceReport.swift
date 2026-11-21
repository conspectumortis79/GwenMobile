import Foundation

struct WebSourceIssue: Codable, Equatable, Hashable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable {
        case blocked
        case unavailable
        case search
    }

    var kind: Kind
    var domain: String
    var reason: String
}

struct WebSourceReport: Codable, Equatable, Hashable, Sendable {
    var used: Int = 0
    var issues: [WebSourceIssue] = []

    var sourceIssues: [WebSourceIssue] { issues.filter { $0.kind != .search } }
    var searchIssues: [WebSourceIssue] { issues.filter { $0.kind == .search } }
    var requested: Int { used + sourceIssues.count }
    var isEmpty: Bool { issues.isEmpty }
    var blockedCount: Int { sourceIssues.filter { $0.kind == .blocked }.count }

    func merging(_ other: WebSourceReport) -> WebSourceReport {
        var merged = self
        merged.used += other.used
        for issue in other.issues where !merged.issues.contains(issue) {
            merged.issues.append(issue)
        }
        return merged
    }

    static func merged(_ first: WebSourceReport?, _ second: WebSourceReport?) -> WebSourceReport? {
        switch (first, second) {
        case (nil, nil): return nil
        case (let first?, nil): return first
        case (nil, let second?): return second
        case (let first?, let second?): return first.merging(second)
        }
    }
}

struct WebResearchResult: Sendable {
    var hits: [WebHit]
    var report: WebSourceReport
}

struct PriceLookupResult: Sendable {
    var hits: [WebHit]
    var report: WebSourceReport
}
