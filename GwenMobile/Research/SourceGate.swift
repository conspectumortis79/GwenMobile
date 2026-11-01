import GwenMobileKit
import Foundation

struct SourceGate: Sendable {
    static let local = SourceGate()

    var reports: SourceReports = .shared

    func isBlocked(_ url: URL) -> Bool {
        SourceGuard.assess(url, reported: reports.isReported(WebSearch.domain(of: url))).isBlocked
    }
}
