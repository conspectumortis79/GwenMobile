import GwenMobileKit

enum SearchShape {
    static let minSentences = 3
    static let minCharsPerSentence = 20
    static let probeChars = 900

    static func sentences(in text: String) -> Int {
        var count = 0
        var sinceTerminator = 0
        for character in text.prefix(probeChars) {
            if character == "." || character == "!" || character == "?" || character == ":" {
                if sinceTerminator > 0 { count += 1 }
                sinceTerminator = 0
            } else if !character.isWhitespace {
                sinceTerminator += 1
            }
        }
        return count
    }

    static func isSubstantial(_ hit: WebHit) -> Bool {
        let probe = String(hit.text.prefix(probeChars))
        let count = sentences(in: probe)
        guard count >= minSentences else { return false }
        return probe.count / count >= minCharsPerSentence
    }

    static func substantial(_ hits: [WebHit]) -> [WebHit] {
        let kept = hits.filter(isSubstantial)
        return kept.isEmpty ? hits : kept
    }
}
