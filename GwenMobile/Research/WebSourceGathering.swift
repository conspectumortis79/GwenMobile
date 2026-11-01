import GwenMobileKit
import Foundation

@MainActor
enum WebSourceGathering {
    static func gather(query: String,
                       question: String,
                       retrieve: @MainActor (String) async throws -> [WebHit],
                       filter: @MainActor ([WebHit]) async -> [WebHit],
                       onRetry: @MainActor () -> Void = {}) async throws -> [WebHit] {
        let hits = try await retrieve(query)
        let kept = await filter(hits)
        guard kept.isEmpty, shouldRetry(query: query, question: question) else { return kept }
        flowMark("WEBHOLEN wiederholung=frage quellen=\(hits.count) behalten=\(kept.count)")
        onRetry()
        let retried = try await retrieve(question)
        return await filter(retried)
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
