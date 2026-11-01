import GwenMobileKit
import Foundation

enum CalendarChoice {

    enum Silent: Equatable {
        case keepCurrent
        case deviceDefault
    }

    enum Outcome: Equatable {
        case keep
        case title(String)
        case unmatched(String)
    }

    static let minWordLength = 4

    static func resolve(requested: String?, available: [String],
                        deviceDefault: String?, silent: Silent) -> Outcome {
        let asked = normalize(requested ?? "")
        if asked.isEmpty {
            guard silent == .deviceDefault else { return .keep }
            let fallback = normalize(deviceDefault ?? "")
            if !fallback.isEmpty, let hit = available.first(where: { normalize($0) == fallback }) {
                return .title(hit)
            }
            return available.first.map { .title($0) } ?? .keep
        }
        if let exact = available.first(where: { normalize($0) == asked
            || squashed($0) == asked.replacingOccurrences(of: " ", with: "") }) {
            return .title(exact)
        }
        let tokens = asked.split(separator: " ").map(String.init).filter { $0.count >= minWordLength }
        if let hit = available.first(where: { candidate in
            let n = normalize(candidate)
            return tokens.contains { n.contains($0) || (n.count >= minWordLength && $0.contains(n)) }
        }) {
            return .title(hit)
        }
        return .unmatched(requested!.trimmed)
    }

    static func normalize(_ text: String) -> String {
        TextFolding.fold(text)
    }

    private static func squashed(_ title: String) -> String {
        normalize(title).replacingOccurrences(of: " ", with: "")
    }
}
