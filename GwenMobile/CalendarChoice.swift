import Foundation

enum CalendarChoice {

    static let privateHints = ["privat", "private", "personlich", "persoenlich", "personal",
                               "zuhause", "home", "familie", "family", "freunde", "friends"]
    static let workHints = ["arbeit", "work", "business", "beruf", "firma", "office", "job",
                            "arbeitgeber", "employer", "corporate", "company"]

    enum Silent: Equatable {
        case keepCurrent
        case preferWork
    }

    enum Outcome: Equatable {
        case keep
        case title(String)
        case unmatched(String)
    }

    static func resolve(requested: String?, available: [String],
                        deviceDefault: String?, silent: Silent) -> Outcome {
        let asked = normalize(requested ?? "")
        if asked.isEmpty {
            guard silent == .preferWork else { return .keep }
            if let work = firstMatch(in: available, hints: workHints) { return .title(work) }
            let fallback = normalize(deviceDefault ?? "")
            if !fallback.isEmpty, let hit = available.first(where: { normalize($0) == fallback }) {
                return .title(hit)
            }
            return available.first.map { .title($0) } ?? .keep
        }
        if let exact = available.first(where: { normalize($0) == asked || squashed($0) == asked.replacingOccurrences(of: " ", with: "") }) {
            return .title(exact)
        }
        if privateHints.contains(where: { asked.contains($0) }), let hit = firstMatch(in: available, hints: privateHints) {
            return .title(hit)
        }
        if workHints.contains(where: { asked.contains($0) }), let hit = firstMatch(in: available, hints: workHints) {
            return .title(hit)
        }
        let tokens = asked.split(separator: " ").map(String.init).filter { $0.count >= 4 }
        if let hit = available.first(where: { candidate in
            let n = normalize(candidate)
            return tokens.contains { n.contains($0) || $0.contains(n) }
        }) {
            return .title(hit)
        }
        return .unmatched((requested ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "„", with: "")
            .replacingOccurrences(of: "“", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private static func squashed(_ title: String) -> String {
        normalize(title).replacingOccurrences(of: " ", with: "")
    }

    private static func firstMatch(in available: [String], hints: [String]) -> String? {
        let normalized = available.map { (title: $0, folded: normalize($0)) }
        if let exact = normalized.first(where: { entry in hints.contains { $0 == entry.folded } }) {
            return exact.title
        }
        return normalized.first(where: { entry in hints.contains { entry.folded.contains($0) } })?.title
    }
}
