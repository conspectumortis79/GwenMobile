import GwenMobileKit
import Foundation

struct PriceWatchCredentials: Equatable, Sendable {
    var baseURL: String
    var key: String
    var model: String
    var thinking: ThinkingDirective

    init(baseURL: String, key: String, model: String, thinking: ThinkingDirective) {
        self.baseURL = baseURL
        self.key = key
        self.model = model
        self.thinking = thinking
    }

    @MainActor
    init(settings: AppSettings) {
        self.init(baseURL: settings.baseURL, key: settings.apiKey, model: settings.chatModel,
                  thinking: settings.thinkingOffDirective(for: settings.chatModel))
    }
}

@MainActor
protocol PriceWatchChecking {
    func check(_ watch: PriceWatch, credentials: PriceWatchCredentials) async throws -> PriceWatchOffer?
}

@MainActor
struct LivePriceWatchChecker: PriceWatchChecking {
    nonisolated static let reportTool = "report_price"
    nonisolated static let maxTokens = 260

    let lookup: any PriceLooking

    nonisolated static func productBlock(_ watch: PriceWatch) -> String {
        var text = "## WATCHED PRODUCT\n" + watch.terms.joined(separator: "\n") + "\n\n"
        text += "## TARGET PRICE\n"
            + Formatters.price(watch.goal, currency: watch.currencyCode) + "\n\n"
        if !watch.wording.isEmpty {
            text += "## USER REQUEST\n" + watch.wording + "\n\n"
        }
        return text
    }

    nonisolated static func context(watch: PriceWatch, region: PriceRegion, hits: [WebHit]) -> String {
        var text = productBlock(watch)
        text += region.promptLine ?? ""
        for (index, hit) in hits.enumerated() {
            text += hit.sourceBlock(numbered: index + 1)
        }
        return text
    }

    nonisolated static func makeRequest(watch: PriceWatch, region: PriceRegion, hits: [WebHit],
                                        credentials: PriceWatchCredentials) throws -> URLRequest {
        try ChatRequest.post(baseURL: credentials.baseURL, key: credentials.key, model: credentials.model,
                             messages: [ChatPayload.system(Prompt.Price.watch()),
                                        ChatPayload.user(context(watch: watch, region: region, hits: hits))],
                             stream: false, thinking: credentials.thinking,
                             timeout: APITimeout.chatRequest,
                             extra: ToolRouter.toolFields(maxTokens: maxTokens, tools: ToolRouter.priceReportTools(),
                                                          toolChoice: ToolRouter.forcedChoice))
    }

    nonisolated static func offer(from data: Data, hits: [WebHit]) -> PriceWatchOffer? {
        guard let call = ToolRouter.toolCalls(from: data).first(where: { $0.name == reportTool }),
              let report = PriceWatchReport(arguments: call.arguments) else { return nil }
        return PriceWatchOffer(report: report, hits: hits)
    }

    func check(_ watch: PriceWatch, credentials: PriceWatchCredentials) async throws -> PriceWatchOffer? {
        let region = PriceRegion.located(watch.regionCode)
        let hits = try await lookup.hits(for: watch.terms, region: region)
        guard !hits.isEmpty else { throw APIError(message: L.t("price_none_found")) }
        let request = try Self.makeRequest(watch: watch, region: region, hits: hits,
                                           credentials: credentials)
        let data = try await HTTP.jsonData(request)
        guard let offer = Self.offer(from: data, hits: hits) else {
            flowMark("PREISWECKER ohne angebot produkt=\(TextLine.oneLine(watch.product, limit: 40))")
            return nil
        }
        flowMark("PREISWECKER angebot produkt=\(TextLine.oneLine(watch.product, limit: 40)) "
                 + "\(offer.traceLine) \(region.traceLine)")
        return offer
    }
}
