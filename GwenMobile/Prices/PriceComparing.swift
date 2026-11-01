import GwenMobileKit
import Foundation

@MainActor
protocol PriceLooking {
    func hits(for terms: [String], region: PriceRegion) async throws -> [WebHit]
}

@MainActor
struct WebPriceLookup: PriceLooking {
    let onStatus: (String?) -> Void

    nonisolated static func merged(_ batches: [[URL]]) -> [URL] {
        var urls: [URL] = []
        var roots: Set<String> = []
        for batch in batches {
            for url in batch {
                let root = WebSearch.root(ofDomain: WebSearch.domain(of: url))
                guard !roots.contains(root) else { continue }
                roots.insert(root)
                urls.append(url)
            }
        }
        return urls
    }

    func hits(for terms: [String], region: PriceRegion) async throws -> [WebHit] {
        defer { onStatus(nil) }
        onStatus(L.t("web_searching"))
        let research = WebResearch(onStatus: { status in onStatus(status) })
        var batches: [[URL]] = []
        for query in PriceSources.queries(for: terms) {
            batches.append(try await research.searchedURLs(query) { term in
                try await WebSearch.searchURLs(term, region: region.searchRegion)
            })
        }
        let urls = Self.merged(batches)
        guard !urls.isEmpty else { throw APIError(message: L.t("web_no_results")) }
        let fetched = await research.fetch(PriceSources.chosen(urls))
        let kept = PriceSources.kept(fetched.hits)
        guard kept.count >= PriceSources.minimumSourceCount else {
            throw APIError(message: fetched.failures.first ?? L.t("price_none_found"))
        }
        return kept
    }
}

struct PriceComparison: Equatable, Sendable {
    let text: String
    let sources: [WebSource]
    let headingKey: String
}

@MainActor
struct PriceComparator {
    static let headingKey = "price_head"

    private let lookup: any PriceLooking

    init(lookup: any PriceLooking) {
        self.lookup = lookup
    }

    nonisolated static func context(question: String, terms: [String], finding: ProductFinding?,
                                    region: PriceRegion, history: [ChatMessage],
                                    hits: [WebHit]) -> String {
        var text = ""
        let transcript = ConversationTranscript.withoutTheNewestQuestion(from: history)
        if !transcript.isEmpty {
            text += PromptLibrary.text("web_earlier_conversation", ["transcript": transcript]) + "\n\n"
        }
        text += finding?.block ?? ""
        text += region.promptLine ?? ""
        if !terms.isEmpty {
            text += PromptLibrary.text("price_product_terms", ["terms": terms.joined(separator: "\n")]) + "\n\n"
        }
        for (index, hit) in hits.enumerated() {
            text += hit.sourceBlock(numbered: index + 1)
        }
        return text + PromptLibrary.text("web_question", ["question": question])
    }

    nonisolated static func makeAnswerRequest(baseURL: String, key: String, model: String,
                                              question: String, terms: [String],
                                              finding: ProductFinding?, region: PriceRegion,
                                              history: [ChatMessage], hits: [WebHit],
                                              thinking: ThinkingDirective) throws -> URLRequest {
        try ChatRequest.post(baseURL: baseURL, key: key, model: model,
                             messages: [ChatPayload.system(Prompt.Price.offers()),
                                        ChatPayload.user(context(question: question, terms: terms,
                                                                 finding: finding, region: region,
                                                                 history: history, hits: hits))],
                             stream: false, thinking: thinking, timeout: APITimeout.researchRequest)
    }

    nonisolated static func searchedTerms(_ terms: [String], finding: ProductFinding?) -> [String] {
        var kept: [String] = []
        for term in terms + (finding?.identityTerms ?? []) where !term.isEmpty && !kept.contains(term) {
            kept.append(term)
        }
        return kept
    }

    func compare(baseURL: String, key: String, model: String, question: String, terms: [String],
                 finding: ProductFinding?, region: PriceRegion, history: [ChatMessage],
                 thinking: ThinkingDirective) async throws -> PriceComparison {
        let wanted = Self.searchedTerms(terms, finding: finding)
        let hits = try await lookup.hits(for: wanted, region: region)
        guard !hits.isEmpty else { throw APIError(message: L.t("price_none_found")) }
        let raw: String? = try await Offload.run {
            let req = try Self.makeAnswerRequest(baseURL: baseURL, key: key, model: model,
                                                 question: question, terms: wanted, finding: finding,
                                                 region: region, history: history, hits: hits,
                                                 thinking: thinking)
            return try await QwenAPI.askText(req)
        }
        let answer = ChatMarkers.strip((raw ?? "").trimmed)
        guard !answer.isEmpty else { throw APIError(message: L.t("web_no_answer")) }
        let priced = PriceEvidence.withPrice(hits).count
        flowMark("PREISVERGLEICH quellen=\(hits.count) preisTreffer=\(priced) "
                 + "\(region.traceLine) zeichen=\(answer.count)")
        return PriceComparison(text: answer, sources: WebResearch.sources(from: hits),
                               headingKey: Self.headingKey)
    }
}
