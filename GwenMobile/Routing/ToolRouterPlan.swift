import GwenMobileKit
import Foundation

extension ToolRouter {
    static func scanReminderRequest(baseURL: String, key: String, model: String, text: String,
                                    context: SendContext, history: [ChatMessage], document: String,
                                    catalog: String = "", eraseHistoryWord: String = "",
                                    thinking: ThinkingDirective) throws -> URLRequest {
        let now = SystemPrompt.currentMoment()
        let system = systemBlock(now: now, context: context,
                                 transcript: ConversationTranscript.withoutTheNewestQuestion(from: history),
                                 catalog: catalog, eraseHistoryWord: eraseHistoryWord,
                                 document: document)
            + "\n\n" + PromptLibrary.text("scan_reminder_answer", ["reminder_tool": reminderTool])
        return try ChatRequest.post(baseURL: baseURL, key: key, model: model,
                                    messages: [ChatPayload.system(system), ChatPayload.user(text)],
                                    stream: false, thinking: thinking, timeout: APITimeout.chatRequest,
                                           extra: toolFields(maxTokens: maxTokens, tools: [reminderFunction()],
                                                      toolChoice: forcedChoice))
    }

    static func plan(asking ask: @escaping @Sendable () async throws -> Data,
                     attempts: Int = decisionAttempts) async -> [ToolDecision] {
        for attempt in 1...max(1, attempts) {
            let data: Data
            do {
                data = try await RateLimitRetry.run { try await Offload.run({ try await ask() }) }
            } catch {
                flowMark("WERKZEUG fehler versuch=\(attempt) "
                         + TextLine.oneLine(error.localizedDescription, limit: 160))
                return []
            }
            let calls = decisions(from: data)
            #if DEBUG
            let rawCalls = toolCalls(from: data)
            let raw = rawCalls.map { "\($0.name)(\($0.arguments))" }.joined(separator: " | ")
            flowMarkPersonal("WERKZEUG roh=" + (raw.isEmpty ? "leer" : TextLine.oneLine(raw, limit: 600)))
            #endif
            if !calls.isEmpty {
                if attempt > 1 { flowMark("WERKZEUG geheilt versuch=\(attempt)") }
                return calls
            }
            flowMark("WERKZEUG fehlt versuch=\(attempt) \(answerShape(of: data))")
        }
        return []
    }

    static func answerShape(of data: Data) -> String {
        guard let found = firstChoice(from: data) else { return "antwort_unlesbar" }
        let text = (found.message["content"] as? String) ?? ""
        return "ende=\(found.choice["finish_reason"] as? String ?? "-") text=\(text.count)"
    }
}
