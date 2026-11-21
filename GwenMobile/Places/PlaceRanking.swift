import GwenMobileKit
import Foundation

struct PlaceCandidate: Equatable {
    let label: String
    let metres: Int?
}

enum PlaceRanking {
    static let keptShare = 0.75

    static func order(_ candidates: [PlaceCandidate], wish: String, byDistance: Bool) -> [Int] {
        let scores = candidates.map { PlaceWishGrounding.overlap(of: $0.label, with: wish) }
        let sorted = candidates.indices.sorted { left, right in
            byDistance ? nearerFit(left, right, scores: scores, candidates: candidates)
                : closerMatch(left, right, scores: scores)
        }
        guard !byDistance, let lead = sorted.first, scores[lead] > 0 else { return sorted }
        let required = PlaceWishGrounding.matchedWords(of: candidates[lead].label, with: wish)
            .filter { !$0.allSatisfy(\.isNumber) }
        return sorted.filter { index in
            guard Double(scores[index]) >= Double(scores[lead]) * keptShare else { return false }
            return required.isSubset(of: PlaceWishGrounding.matchedWords(of: candidates[index].label,
                                                                        with: wish))
        }
    }

    static func queries(terms: [String], wish: String, limit: Int) -> [String] {
        var asked = Array(terms.filter { !$0.isEmpty }.prefix(limit))
        let own = wish.trimmed
        if !own.isEmpty, !asked.contains(own) { asked.append(own) }
        return asked
    }

    private static func closerMatch(_ left: Int, _ right: Int, scores: [Int]) -> Bool {
        scores[left] != scores[right] ? scores[left] > scores[right] : left < right
    }

    private static func nearerFit(_ left: Int, _ right: Int, scores: [Int], candidates: [PlaceCandidate]) -> Bool {
        let (fitsLeft, fitsRight) = (scores[left] > 0, scores[right] > 0)
        if fitsLeft != fitsRight { return fitsLeft }
        let (nearLeft, nearRight) = (candidates[left].metres ?? .max, candidates[right].metres ?? .max)
        return nearLeft != nearRight ? nearLeft < nearRight : left < right
    }
}
