import GwenMobileKit

enum SourceSimilarity {
    static let shingleWords = 5
    static let minimumWords = 12
    static let duplicateThreshold = 0.4

    static func similarity(_ first: String, _ second: String) -> Double {
        let left = shingles(first)
        let right = shingles(second)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let union = left.union(right)
        guard !union.isEmpty else { return 0 }
        return Double(left.intersection(right).count) / Double(union.count)
    }

    static func isDuplicate(_ first: String, _ second: String) -> Bool {
        similarity(first, second) >= duplicateThreshold
    }

    static func clusters(_ hits: [WebHit]) -> [[Int]] {
        group(hits.count) { isDuplicate(hits[$0].text, hits[$1].text) }
    }

    static func independentGroups(_ hits: [WebHit]) -> [[Int]] {
        let copies = clusters(hits)
        return group(hits.count) { first, second in
            if sameDomain(hits[first], hits[second]) { return true }
            return copies.contains { $0.contains(first) && $0.contains(second) }
        }
    }

    static func originNumber(of index: Int, groups: [[Int]]) -> Int? {
        guard let group = groups.first(where: { $0.contains(index) }),
              group.count > 1, group.first != index else { return nil }
        return group[0] + 1
    }

    static func originAssignment(total: Int, groups: [[Int]]) -> [Int] {
        var assignment = Array(repeating: 0, count: total)
        for (position, group) in groups.enumerated() {
            for index in group where index >= 0 && index < total { assignment[index] = position }
        }
        return assignment
    }

    private static func sameDomain(_ first: WebHit, _ second: WebHit) -> Bool {
        let left = WebSearch.root(ofDomain: first.domain)
        let right = WebSearch.root(ofDomain: second.domain)
        return !left.isEmpty && left == right
    }

    private static func shingles(_ text: String) -> Set<UInt64> {
        let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard words.count >= minimumWords else { return [] }
        var result = Set<UInt64>()
        for start in 0...(words.count - shingleWords) {
            result.insert(hash(words[start..<(start + shingleWords)].joined(separator: " ")))
        }
        return result
    }

    private static func hash(_ text: String) -> UInt64 {
        var value: UInt64 = 1469598103934665603
        for byte in text.utf8 {
            value ^= UInt64(byte)
            value = value &* 1099511628211
        }
        return value
    }

    private static func group(_ count: Int, related: (Int, Int) -> Bool) -> [[Int]] {
        guard count > 0 else { return [] }
        var parent = Array(0..<count)
        func find(_ value: Int) -> Int {
            var current = value
            while parent[current] != current {
                parent[current] = parent[parent[current]]
                current = parent[current]
            }
            return current
        }
        for first in 0..<count {
            for second in (first + 1)..<count where related(first, second) {
                let left = find(first)
                let right = find(second)
                if left != right { parent[max(left, right)] = min(left, right) }
            }
        }
        var buckets: [Int: [Int]] = [:]
        for index in 0..<count {
            buckets[find(index), default: []].append(index)
        }
        return buckets.values.sorted { $0[0] < $1[0] }
    }
}
