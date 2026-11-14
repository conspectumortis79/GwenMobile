import Foundation

struct ProviderBalance: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        var total: String
        var currency: String
        var granted: String? = nil
        var toppedUp: String? = nil
    }

    enum Status: Equatable, Sendable {
        case available
        case unavailable
        case usageOnly
    }

    var status: Status
    var entries: [Entry]
    var limit: String? = nil
    var usage: String? = nil
    var purchasedCredits: String? = nil
    var usedCredits: String? = nil
}
