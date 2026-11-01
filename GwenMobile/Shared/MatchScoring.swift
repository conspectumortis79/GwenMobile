import Foundation

public protocol MatchCandidate: Sendable {
    var titleHaystack: String { get }
    var detailHaystack: String { get }
    var matchDate: Date? { get }
}

public enum MatchText {
    public static func title(_ text: String) -> String { TextFolding.fold(text) }

    public static func detail(_ location: String, _ notes: String) -> String {
        TextFolding.fold("\(location) \(notes)")
    }
}

public enum MatchStrength: Int, Comparable, Sendable {
    case none = 0
    case detail = 1
    case title = 2

    public static func < (lhs: MatchStrength, rhs: MatchStrength) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum MatchScoring {
    public static let minWordLength = 4

    public static func words(in query: String) -> [String] {
        TextFolding.fold(query)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    public static func carrying(_ words: [String]) -> [String] {
        words.filter { $0.count >= minWordLength }
    }

    public static func strength<C: MatchCandidate>(of candidate: C, word: String) -> MatchStrength {
        if candidate.titleHaystack.contains(word) { return .title }
        if candidate.detailHaystack.contains(word) { return .detail }
        return .none
    }

    public static func strength<C: MatchCandidate>(of candidate: C, words: [String]) -> MatchStrength {
        carrying(words).map { strength(of: candidate, word: $0) }.max() ?? .none
    }

    public static func bestIndex<C: MatchCandidate>(in candidates: [C], query: String, now: Date,
                                             requiresTitle: Bool = true) -> Int? {
        let terms = carrying(words(in: query))
        guard !terms.isEmpty else { return nil }
        let wanted: MatchStrength = requiresTitle ? .title : .detail
        var best: (index: Int, strength: MatchStrength, distance: TimeInterval)?
        for (index, candidate) in candidates.enumerated() {
            let strength = strength(of: candidate, words: terms)
            guard strength >= wanted else { continue }
            let distance = candidate.matchDate.map { abs($0.timeIntervalSince(now)) }
                ?? .greatestFiniteMagnitude
            let improves = best.map { current in
                strength > current.strength || (strength == current.strength && distance < current.distance)
            } ?? true
            if improves { best = (index, strength, distance) }
        }
        return best?.index
    }
}
