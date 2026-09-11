import Foundation

@MainActor
struct WebResearch {
    static let minimumSourceCount = 1

    var onStatus: (String) -> Void

    func hits(for query: String) async throws -> [WebHit] {
        let urls = try await WebSearch.search(query)
        var found: [WebHit] = []
        for (index, url) in urls.enumerated() {
            onStatus("\(L.t("web_fetching")) (\(index + 1)/\(urls.count)) \(WebSearch.domain(of: url))")
            if let hit = try? await WebSearch.fetchText(url) { found.append(hit) }
        }
        guard found.count >= Self.minimumSourceCount else { throw APIError(message: L.t("web_no_results")) }
        return found
    }

    static func dataDigest(from hits: [WebHit], limit: Int = ChartPlanner.maxDataChars) -> String {
        var digest = ""
        for (index, hit) in hits.enumerated() {
            digest += "## Quelle [\(index + 1)] \(hit.title) — \(hit.domain)\n\(hit.text)\n\n"
            if digest.count >= limit { break }
        }
        return String(digest.prefix(limit))
    }

    static func sources(from hits: [WebHit]) -> [WebSource] {
        hits.map { WebSource(title: $0.title, url: $0.url, domain: $0.domain) }
    }

    static func priorResearch(from history: [ChatMessage],
                              limit: Int = ChartPlanner.maxDataChars) -> (digest: String, sources: [WebSource]) {
        let answers = history.filter { $0.role == .assistant && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var digest = ""
        var sources: [WebSource] = []
        for answer in answers.suffix(maxPriorAnswers) {
            let refs = (answer.sources ?? []).enumerated()
                .map { "Quelle [\($0.offset + 1)] \($0.element.title) — \($0.element.domain) \($0.element.url)" }
                .joined(separator: "\n")
            digest += "## Gespeicherte Antwort\n\(answer.text)\n"
            if !refs.isEmpty { digest += "\n## Gefundene Quellen\n\(refs)\n" }
            digest += "\n"
            if let last = answer.sources, !last.isEmpty { sources = last }
            if digest.count >= limit { break }
        }
        return (String(digest.prefix(limit)), sources)
    }

    static let maxPriorAnswers = 2
}
