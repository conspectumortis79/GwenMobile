import Foundation

@MainActor
struct WebResearch {
    var onStatus: (String) -> Void

    func hits(for query: String) async throws -> [WebHit] {
        let urls = try await WebSearch.search(query)
        var found: [WebHit] = []
        for (index, url) in urls.enumerated() {
            onStatus("\(L.t("web_fetching")) (\(index + 1)/\(urls.count)) \(WebSearch.domain(of: url))")
            if let hit = try? await WebSearch.fetchText(url) { found.append(hit) }
        }
        guard found.count >= 2 else { throw APIError(message: L.t("web_no_results")) }
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
}
