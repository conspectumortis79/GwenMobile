import GwenMobileKit
import Foundation

struct TranslationJob: Equatable, Sendable, CustomStringConvertible {
    var text: String
    var targetCode: String
    var sourceCode: String? = nil
    var fromChat = false

    var isEmpty: Bool { text.trimmed.isEmpty }
    var target: TranslationLanguage? { TranslationLanguages.withCode(targetCode) }
    var pairLabel: String { TranslationLanguages.pairLabel(from: sourceCode, to: targetCode) }
    var trace: String { "zeichen=\(text.count) zeilen=\(text.components(separatedBy: "\n").count)" }
    var description: String { "translate → \(targetCode) (\(trace))" }

    func withText(_ replacement: String, fromChat: Bool) -> TranslationJob {
        TranslationJob(text: replacement, targetCode: targetCode, sourceCode: sourceCode,
                       fromChat: fromChat)
    }

    func withSource(_ code: String) -> TranslationJob {
        TranslationJob(text: text, targetCode: targetCode, sourceCode: code, fromChat: fromChat)
    }

    @MainActor func resolved(with carry: AnswerCarry) -> TranslationJob {
        guard fromChat || isEmpty else { return self }
        let answer = carry.lastAnswerText
        guard !answer.isEmpty else { return self }
        return withText(answer, fromChat: true)
    }
}

enum TranslationIntent {
    static func chatText(excluding message: String, in history: [ChatMessage]) -> String? {
        let wanted = TranslationFold.of(message)
        for message in history.reversed() {
            let body = message.text.trimmed
            guard !body.isEmpty, TranslationFold.of(body) != wanted else { continue }
            return body
        }
        return nil
    }
}

extension ToolDecision {
    func withChatText(excluding message: String, history: [ChatMessage]) -> ToolDecision {
        guard case .translate(let job) = route, job.isEmpty,
              let chat = TranslationIntent.chatText(excluding: message, in: history) else { return self }
        return ToolDecision(route: .translate(job.withText(chat, fromChat: true)))
    }
}
