import GwenMobileKit
import Foundation

enum ContactLookupResult: Equatable, Sendable {
    case denied
    case unreadable(String)
    case resolved(ContactResolution, cards: Int)

    var trace: String {
        switch self {
        case .denied: return "zugriff=nein"
        case .unreadable(let detail): return "lesen=fehler " + detail
        case .resolved(let resolution, let cards):
            return "karten=\(cards) ergebnis=\(ContactLookup.describe(resolution))"
        }
    }
}

struct ContactLookup: Sendable {
    let directory: any ContactDirectory

    func resolve(_ request: ContactRequest) async -> ContactLookupResult {
        guard await directory.access() == .granted else { return .denied }
        do {
            let cards = try await directory.cards()
            return .resolved(ContactMatching.resolve(request, in: cards), cards: cards.count)
        } catch {
            return .unreadable(TextLine.oneLine(error.localizedDescription, limit: 120))
        }
    }

    static func describe(_ resolution: ContactResolution) -> String {
        switch resolution {
        case .unique(let target, _): return "eindeutig:\(target.name)"
        case .ambiguous(let names): return "mehrdeutig:\(names.joined(separator: "|"))"
        case .unsure(let names): return "unsicher:\(names.joined(separator: "|"))"
        case .noNumber(let name): return "ohne_nummer:\(name)"
        case .notFound: return "nicht_gefunden"
        }
    }
}
