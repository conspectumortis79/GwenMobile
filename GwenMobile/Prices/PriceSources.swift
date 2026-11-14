import GwenMobileKit
import Foundation

enum PriceSources {
    static let maxTerms = 3
    static let maxHits = 4
    static let fetchWindow = 6
    static let minimumSourceCount = 1
    static let queryChars = 90

    static func queries(for terms: [String]) -> [String] {
        uniqueTerms(terms, limit: maxTerms, chars: queryChars) { $0 == $1 }
    }

    static func uniqueTerms(_ raw: [String], limit: Int, chars: Int,
                            same: (String, String) -> Bool) -> [String] {
        var kept: [String] = []
        for term in raw {
            let text = TextLine.oneLine(term, limit: chars).trimmed
            guard !text.isEmpty, !kept.contains(where: { same($0, text) }) else { continue }
            kept.append(text)
            if kept.count == limit { break }
        }
        return kept
    }

    static func chosen(_ urls: [URL]) -> [URL] {
        Array(urls.prefix(fetchWindow))
    }

    static func kept(_ hits: [WebHit]) -> [WebHit] {
        Array(PriceEvidence.ranked(hits).prefix(maxHits))
    }
}
