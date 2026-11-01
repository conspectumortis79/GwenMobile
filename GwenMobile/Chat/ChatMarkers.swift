import GwenMobileKit
import Foundation

enum SearchMarker {
    static let token = "[[SEARCH]]"
}

struct RouteDecision: Equatable, Sendable {
    var search = false
}

enum ChatMarkers {
    private static let decoration = CharacterSet(charactersIn: " \n\t")
    private static let leftoverCharacters: Set<Character> = [" ", "\t", "-", "*", "\u{2022}", ">",
                                                            "\u{201C}", "\u{201D}", "\"", "`",
                                                            "\u{201E}", "\u{201A}"]
    private static let tokens = [SearchMarker.token]
    private static let doubledSpaces = try? NSRegularExpression(pattern: "[ \\t]{2,}")
    private static let spaceBeforePunctuation = try? NSRegularExpression(pattern: "[ \\t]+([.,;:!?])")

    static func parse(_ text: String) -> RouteDecision {
        var decision = RouteDecision()
        decision.search = text.contains(SearchMarker.token)
        return decision
    }

    static func strip(_ text: String) -> String {
        guard tokens.contains(where: { text.contains($0) }) else { return text }
        var rest = text
        for token in tokens {
            rest = rest.replacingOccurrences(of: token, with: "")
        }
        rest = rest.components(separatedBy: "\n")
            .filter { !isMarkerLeftover($0) }
            .joined(separator: "\n")
        rest = collapse(doubledSpaces, in: rest, with: " ")
        rest = collapse(spaceBeforePunctuation, in: rest, with: "$1")
        return rest.trimmingCharacters(in: decoration)
    }

    private static func isMarkerLeftover(_ line: String) -> Bool {
        guard !line.isEmpty else { return false }
        var carriesDecoration = false
        for character in line {
            guard leftoverCharacters.contains(character) else { return false }
            if !character.isWhitespace { carriesDecoration = true }
        }
        return carriesDecoration
    }

    private static func collapse(_ regex: NSRegularExpression?, in text: String, with template: String) -> String {
        guard let regex else { return text }
        let ns = text as NSString
        return regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length),
                                             withTemplate: template)
    }
}
