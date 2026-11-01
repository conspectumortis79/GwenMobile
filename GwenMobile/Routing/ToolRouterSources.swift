import GwenMobileKit
import Foundation

extension ToolRouter {
    static let sourceExcerptChars = 400

    static func keptSources(baseURL: String, key: String, model: String, question: String,
                            hits: [WebHit], thinking: ThinkingDirective,
                            ask: @Sendable (URLRequest) async throws -> Data) async -> [WebHit] {
        guard hits.count > 1 else { return hits }
        let started = ContinuousClock.now
        do {
            let request = try await Offload.run {
                try sourceFilterRequest(baseURL: baseURL, key: key, model: model,
                                        question: question, hits: hits, thinking: thinking)
            }
            let data = try await ask(request)
            guard let indexes = sourceIndexes(from: data, count: hits.count) else { return hits }
            let kept = indexes.map { hits[$0] }
            flowMark("QUELLENFILTER quellen=\(hits.count) behalten=\(kept.count) "
                     + "dauer_ms=\(msOf(started.duration(to: .now)))")
            return kept
        } catch {
            flowMark("QUELLENFILTER fehlgeschlagen dauer_ms=\(msOf(started.duration(to: .now))) "
                     + TextLine.oneLine(error.localizedDescription, limit: 80))
            return hits
        }
    }

    static func sourceFilterRequest(baseURL: String, key: String, model: String, question: String,
                                    hits: [WebHit], thinking: ThinkingDirective) throws -> URLRequest {
        try ChatRequest.post(baseURL: baseURL, key: key, model: model,
                             messages: [ChatPayload.system(PromptLibrary.text("router_source_filter")),
                                        ChatPayload.user(PromptLibrary.text("router_source_filter_user",
                                                                            ["question": question,
                                                                             "sources": sourceList(hits)]))],
                             stream: false, thinking: thinking, timeout: APITimeout.chatRequest,
                             extra: toolFields(maxTokens: maxTokens, tools: sourceFilterTools(),
                                               toolChoice: forcedChoice))
    }

    static func sourceIndexes(from data: Data, count: Int) -> [Int]? {
        guard let call = toolCalls(from: data).first(where: { $0.name == keepSourcesTool }),
              let arguments = call.arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: arguments) as? [String: Any],
              let raw = object["sources"] as? [Any] else { return nil }
        guard !raw.isEmpty else { return [] }
        var seen = Set<Int>()
        var indexes: [Int] = []
        for value in raw {
            guard let number = LooseNumber.value(value), number.isFinite,
                  let converted = Int(exactly: number.rounded(.towardZero)),
                  converted >= 1, converted <= count else { continue }
            let index = converted - 1
            guard seen.insert(index).inserted else { continue }
            indexes.append(index)
        }
        return indexes.isEmpty ? nil : indexes
    }

    private static func sourceList(_ hits: [WebHit]) -> String {
        hits.enumerated().map { index, hit in
            "[\(index + 1)] \(hit.title) - \(hit.domain)\n\(hit.url)\n"
                + TextLine.oneLine(hit.text, limit: sourceExcerptChars)
        }.joined(separator: "\n\n")
    }
}
