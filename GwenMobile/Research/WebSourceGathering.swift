import GwenMobileKit
import Foundation

@MainActor
enum WebSourceGathering {
    static func gather(query: String,
                       question: String,
                       retrieve: @MainActor (String) async throws -> [WebHit],
                       filter: @MainActor ([WebHit]) async -> [WebHit],
                       onRetry: @MainActor () -> Void = {}) async throws -> [WebHit] {
        try await gatherWithReport(query: query, question: question,
                                   retrieve: { term in
                                       WebResearchResult(hits: try await retrieve(term), report: WebSourceReport())
                                   },
                                   filter: filter, onRetry: onRetry).hits
    }

    static func gatherWithReport(query: String,
                                 question: String,
                                 retrieve: @MainActor (String) async throws -> WebResearchResult,
                                 filter: @MainActor ([WebHit]) async -> [WebHit],
                                 onRetry: @MainActor () -> Void = {}) async throws -> WebResearchResult {
        let hits = try await retrieve(query)
        let kept = await filter(hits.hits)
        var result = WebResearchResult(hits: kept, report: hits.report)
        result.report.used = kept.count
        guard kept.isEmpty, shouldRetry(query: query, question: question) else { return result }
        flowMark("WEBHOLEN wiederholung=frage quellen=\(hits.hits.count) behalten=\(kept.count)")
        onRetry()
        let retried = try await retrieve(question)
        let retriedKept = await filter(retried.hits)
        var retriedResult = WebResearchResult(hits: retriedKept, report: retried.report)
        retriedResult.report.used = retriedKept.count
        return retriedResult
    }

    static func shouldRetry(query: String, question: String) -> Bool {
        let asked = normalized(question)
        guard !asked.isEmpty else { return false }
        return asked.compare(normalized(query), options: [.caseInsensitive, .diacriticInsensitive])
            != .orderedSame
    }

    private static func normalized(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
