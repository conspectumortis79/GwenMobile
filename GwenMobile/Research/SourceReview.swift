import GwenMobileKit
import Foundation

enum ClaimVerdict: String, Codable, Equatable, Hashable, Sendable {
    case supported
    case unsupported
    case contradicted
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ClaimVerdict(rawValue: raw.trimmed.lowercased())
            ?? .unknown
    }
}

struct SourceReview: Equatable, Hashable, Sendable {
    struct Claim: Codable, Equatable, Hashable, Sendable {
        var claim: String = ""
        var sources: [Int]?
        var supported: Bool?
        var verdict: ClaimVerdict?
        var contradicts: [Int]?

        var resolvedVerdict: ClaimVerdict? {
            if let verdict { return verdict == .unknown ? nil : verdict }
            guard let supported else { return nil }
            return supported ? .supported : .unsupported
        }
    }

    struct ClaimResult: Codable, Equatable, Hashable, Sendable {
        var claim: String = ""
        var verdict: ClaimVerdict = .supported
        var sources: [Int] = []
        var contradicts: [Int] = []
    }

    struct ClaimMark: Equatable, Hashable, Sendable {
        var range: Range<String.Index>
        var resultIndex: Int
        var verdict: ClaimVerdict
    }

    struct CitedSpan: Equatable, Sendable {
        var text: String
        var range: Range<String.Index>
        var numbers: [Int]
    }

    var sourceDomains: Int = 0
    var sourceGroups: [[Int]] = []
    var citedSources: Int = 0
    var citedOrigins: Int = 0
    var citedClaims: Int = 0
    var crossChecked: Bool = false
    var checkedClaims: Int = 0
    var unsupported: [String] = []
    var contradicted: [String] = []
    var results: [ClaimResult] = []
    var verified: Bool = false

    var singleSource: Bool { citedClaims > 0 && citedOrigins == 1 }
    var verificationMissing: Bool { citedClaims > 0 && !verified }
    var citedDuplicates: Int { max(0, citedSources - citedOrigins) }
    var copyCount: Int { sourceGroups.reduce(0) { $0 + max(0, $1.count - 1) } }
    var warnings: [ClaimResult] { results.filter { $0.verdict != .supported } }

    func marks(in answer: String) -> [ClaimMark] {
        let spans = Self.citedSpans(in: answer)
        guard !spans.isEmpty else { return [] }
        var candidates: [(result: Int, span: Int, range: Range<String.Index>, score: Double)] = []
        for (index, result) in results.enumerated() where result.verdict != .supported {
            for (position, span) in spans.enumerated() {
                guard let score = Self.matchScore(result, span) else { continue }
                let range = Self.sentenceMatch(result, in: span, answer: answer) ?? span.range
                candidates.append((index, position, range, score))
            }
        }
        candidates.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.span != $1.span { return $0.span < $1.span }
            return $0.result < $1.result
        }
        var takenResults = Set<Int>()
        var takenSpans = Set<Int>()
        var found: [ClaimMark] = []
        for candidate in candidates {
            guard !takenResults.contains(candidate.result),
                  !takenSpans.contains(candidate.span) else { continue }
            takenResults.insert(candidate.result)
            takenSpans.insert(candidate.span)
            found.append(ClaimMark(range: candidate.range, resultIndex: candidate.result,
                                   verdict: results[candidate.result].verdict))
        }
        return found.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    func shifted(by offset: Int, sources count: Int) -> SourceReview {
        guard offset > 0, count > 0 else { return self }
        func moved(_ numbers: [Int]) -> [Int] { numbers.map { (1...count).contains($0) ? $0 + offset : $0 } }
        var review = self
        review.results = results.map { result in
            var moving = result
            moving.sources = moved(result.sources)
            moving.contradicts = moved(result.contradicts)
            return moving
        }
        review.sourceGroups = sourceGroups.map { group in group.map { $0 + offset } }
        return review
    }

    func applying(_ claims: [Claim]) -> SourceReview {
        let decided = claims.compactMap { claim -> ClaimResult? in
            guard let verdict = claim.resolvedVerdict else { return nil }
            let text = TextLine.oneLine(claim.claim, limit: 120)
            guard !text.isEmpty else { return nil }
            let sources = (claim.sources ?? []).filter { $0 >= 1 }
            guard !sources.isEmpty || verdict != .supported else { return nil }
            return ClaimResult(claim: text, verdict: verdict, sources: sources,
                               contradicts: (claim.contradicts ?? []).filter { $0 >= 1 })
        }
        guard !decided.isEmpty else { return self }
        var review = self
        review.verified = true
        review.checkedClaims = decided.count
        review.results = decided
        review.unsupported = decided.filter { $0.verdict == .unsupported }.map(\.claim)
        review.contradicted = decided.filter { $0.verdict == .contradicted }.map(\.claim)
        return review
    }

    static func analyze(answer: String, hits: [WebHit]) -> SourceReview {
        var review = SourceReview()
        review.sourceDomains = Set(hits.map { WebSearch.root(ofDomain: $0.domain) }).count
        review.sourceGroups = SourceSimilarity.clusters(hits)
        let assignment = SourceSimilarity.originAssignment(total: hits.count,
                                                           groups: SourceSimilarity.independentGroups(hits))
        var origins = Set<Int>()
        var cited = Set<Int>()
        var claims = 0
        for unit in citedUnits(in: answer) {
            let numbers = unit.numbers.filter { $0 >= 1 && $0 <= hits.count }
            guard !numbers.isEmpty else { continue }
            claims += 1
            for number in numbers {
                let index = number - 1
                cited.insert(index)
                origins.insert(assignment[index])
            }
        }
        review.citedClaims = claims
        review.citedSources = cited.count
        review.citedOrigins = origins.count
        review.crossChecked = origins.count >= 2
        return review
    }

    static func coverageNote(hits: [WebHit]) -> String {
        let roots = Set(hits.map { WebSearch.root(ofDomain: $0.domain) })
        if roots.count == 1, let only = roots.first, !only.isEmpty {
            return PromptLibrary.field("research_source_note", "single_domain", ["domain": only])
        }
        guard hits.count > 1, SourceSimilarity.independentGroups(hits).count == 1 else { return "" }
        return PromptLibrary.field("research_source_note", "single_origin")
    }

    static func citedSpans(in answer: String) -> [CitedSpan] {
        var spans: [CitedSpan] = []
        var cursor = answer.startIndex
        for unit in citedUnits(in: answer) {
            guard let range = answer.range(of: unit.text, range: cursor..<answer.endIndex) else { continue }
            spans.append(CitedSpan(text: unit.text, range: range, numbers: unit.numbers))
            cursor = range.upperBound
        }
        return spans
    }

    private static let bulletPrefix = try? NSRegularExpression(pattern: "^(?:[-*\u{2022}]|\\d+[.)])\\s+")
    private static let sentenceBreak = try? NSRegularExpression(pattern: "(?<=[.!?])\\s+")

    static func citedUnits(in answer: String) -> [(text: String, numbers: [Int])] {
        var units: [String] = []
        for rawLine in answer.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if isBulletLine(line) {
                units.append(line)
            } else {
                units.append(contentsOf: sentences(in: line))
            }
        }
        return units.compactMap { unit in
            let numbers = citationNumbers(in: unit)
            return numbers.isEmpty ? nil : (unit, numbers)
        }
    }

    private static func isBulletLine(_ line: String) -> Bool {
        guard let bulletPrefix else { return false }
        return bulletPrefix.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }

    static func citationNumbers(in text: String) -> [Int] {
        guard let regex = CitationMarkers.regex else { return [] }
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length))
            .flatMap { CitationMarkers.numbers(in: source.substring(with: $0.range(at: 1))) }
    }

    private static let matchOverlap = 0.75

    private static func matchScore(_ result: ClaimResult, _ span: CitedSpan) -> Double? {
        let claimWords = matchWords(result.claim)
        guard !claimWords.isEmpty else { return nil }
        let claimText = claimWords.joined(separator: " ")
        let spanWords = matchWords(span.text)
        var score: Double
        if claimWords.count >= 2, spanWords.joined(separator: " ").contains(claimText) {
            score = 1
        } else if claimWords.count >= 2 {
            let shared = Double(Set(claimWords).intersection(spanWords).count) / Double(claimWords.count)
            guard shared >= matchOverlap else { return nil }
            score = shared
        } else if spanWords.contains(claimText) {
            score = 1
        } else {
            return nil
        }
        if !Set(result.sources).isDisjoint(with: span.numbers) { score += 0.05 }
        return score
    }

    private static func matchWords(_ text: String) -> [String] {
        TextFolding.fold(text).split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private static func sentences(in line: String) -> [String] {
        guard let sentenceBreak else { return [line] }
        let broken = sentenceBreak.stringByReplacingMatches(in: line,
                                                            range: NSRange(line.startIndex..., in: line),
                                                            withTemplate: "\n")
        return broken.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    static func sentenceMatch(_ result: ClaimResult, in span: CitedSpan,
                                      answer: String) -> Range<String.Index>? {
        let sentences = sentenceSpans(in: span, answer: answer)
        guard sentences.count > 1, let spanScore = matchScore(result, span) else { return nil }
        var best: (score: Double, range: Range<String.Index>)?
        for sentence in sentences {
            guard let score = matchScore(result, sentence) else { continue }
            if let current = best {
                if score > current.score { best = (score, sentence.range) }
            } else {
                best = (score, sentence.range)
            }
        }
        guard let best, best.score >= spanScore else { return nil }
        return best.range
    }

    private static func sentenceSpans(in span: CitedSpan, answer: String) -> [CitedSpan] {
        var spans: [CitedSpan] = []
        var start = span.range.lowerBound
        var index = start
        while index < span.range.upperBound {
            let character = answer[index]
            let next = answer.index(after: index)
            if character == "." || character == "!" || character == "?" {
                var end = next
                while end < span.range.upperBound, answer[end].isWhitespace {
                    end = answer.index(after: end)
                }
                if end > next || end == span.range.upperBound,
                   !breaksAfterOrdinal(answer, punctuation: index, next: end, lower: span.range.lowerBound) {
                    appendSentence(start..<end, to: &spans, answer: answer, numbers: span.numbers)
                    start = end
                }
            }
            index = next
        }
        if start < span.range.upperBound {
            appendSentence(start..<span.range.upperBound, to: &spans, answer: answer, numbers: span.numbers)
        }
        return spans
    }

    private static func breaksAfterOrdinal(_ answer: String, punctuation: String.Index,
                                           next: String.Index, lower: String.Index) -> Bool {
        guard punctuation > lower, next < answer.endIndex else { return false }
        guard answer[answer.index(before: punctuation)].isNumber else { return false }
        return answer[next].isUppercase
    }

    private static func appendSentence(_ range: Range<String.Index>, to spans: inout [CitedSpan],
                                       answer: String, numbers: [Int]) {
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower < upper, answer[lower].isWhitespace { lower = answer.index(after: lower) }
        while upper > lower, answer[answer.index(before: upper)].isWhitespace {
            upper = answer.index(before: upper)
        }
        guard lower < upper else { return }
        spans.append(CitedSpan(text: String(answer[lower..<upper]), range: lower..<upper, numbers: numbers))
    }
}

extension SourceReview: Codable {
    enum CodingKeys: String, CodingKey {
        case sourceDomains, sourceGroups, citedSources, citedOrigins, citedClaims, crossChecked, checkedClaims,
             unsupported, contradicted, results, verified
    }

    enum LegacyKeys: String, CodingKey {
        case citedDomains
    }

    init(from decoder: Decoder) throws {
        let fields = try LenientFields<CodingKeys>(decoder)
        let domains = try LenientFields<LegacyKeys>(decoder).content(Int.self, .citedDomains, fallback: 0)
        sourceDomains = fields.content(Int.self, .sourceDomains, fallback: 0)
        sourceGroups = fields.content([[Int]].self, .sourceGroups, fallback: [])
        citedSources = fields.content(Int.self, .citedSources, fallback: 0)
        citedOrigins = fields.content(Int.self, .citedOrigins, fallback: domains)
        citedClaims = fields.content(Int.self, .citedClaims, fallback: 0)
        crossChecked = fields.content(Bool.self, .crossChecked, fallback: domains >= 2)
        checkedClaims = fields.content(Int.self, .checkedClaims, fallback: 0)
        unsupported = fields.content([String].self, .unsupported, fallback: [])
        contradicted = fields.content([String].self, .contradicted, fallback: [])
        results = fields.content([ClaimResult].self, .results, fallback: [])
        verified = fields.content(Bool.self, .verified, fallback: false)
    }
}

struct SourceVerifier: Sendable {
    var baseURL: String
    var key: String
    var model: String
    var thinking: ThinkingDirective
    var ask: @Sendable (URLRequest) async throws -> String? = { try await QwenAPI.askText($0) }

    func apply(to review: SourceReview, answer: String, hits: [WebHit]) async -> SourceReview {
        guard review.citedClaims > 0 else { return review }
        do {
            let request = try await Offload.run {
                try Self.makeRequest(baseURL: baseURL, key: key, model: model,
                                     answer: answer, hits: hits, thinking: thinking)
            }
            for attempt in 1...2 {
                guard let raw = try await ask(request), let claims = Self.parse(raw) else {
                    flowMark("PRUEFUNG verworfen grund=unlesbar versuch=\(attempt)")
                    continue
                }
                let applied = review.applying(claims)
                if applied.verified { return applied }
                let withoutSources = claims.filter { ($0.sources ?? []).filter { $0 >= 1 }.isEmpty }.count
                let withoutVerdict = claims.filter { $0.resolvedVerdict == nil }.count
                flowMark("PRUEFUNG verworfen versuch=\(attempt) urteile=\(claims.count) "
                         + "ohne_quelle=\(withoutSources) ohne_urteil=\(withoutVerdict)")
            }
            return review
        } catch {
            flowMark("PRUEFUNG fehlgeschlagen \(TextLine.oneLine(error.localizedDescription, limit: 80))")
            return review
        }
    }

    nonisolated static func makeRequest(baseURL: String, key: String, model: String,
                                        answer: String, hits: [WebHit],
                                        thinking: ThinkingDirective) throws -> URLRequest {
        try ChatRequest.post(baseURL: baseURL, key: key, model: model,
                             messages: [ChatPayload.system(PromptLibrary.text("research_verify")),
                                        ChatPayload.user(userContext(answer: answer, hits: hits))],
                             stream: false, thinking: thinking, timeout: APITimeout.researchRequest)
    }

    nonisolated static func userContext(answer: String, hits: [WebHit]) -> String {
        let numbers = Set(SourceReview.citationNumbers(in: answer))
            .filter { $0 >= 1 && $0 <= hits.count }
            .sorted()
        let groups = SourceSimilarity.clusters(hits)
        var sources = ""
        for number in numbers {
            sources += hits[number - 1].sourceBlock(
                numbered: number,
                copyOf: SourceSimilarity.originNumber(of: number - 1, groups: groups))
        }
        return PromptLibrary.text("research_verify_user", ["answer": answer, "sources": sources])
    }

    nonisolated static func parse(_ raw: String) -> [SourceReview.Claim]? {
        for candidate in candidates(raw) {
            guard let data = candidate.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(Payload.self, from: data) else { continue }
            return payload.claims.filter { !$0.claim.trimmed.isEmpty }
        }
        return nil
    }

    private struct Payload: Decodable {
        var claims: [SourceReview.Claim]
    }

    private static func candidates(_ raw: String) -> [String] {
        var text = raw.replacingOccurrences(of: "```json", with: "")
        text = text.replacingOccurrences(of: "```", with: "")
        text = text.trimmed
        var found = [text]
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end {
            found.append(String(text[start...end]))
        }
        return found
    }
}
