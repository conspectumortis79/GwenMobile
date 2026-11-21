import GwenMobileKit
import Foundation
import NaturalLanguage

enum SpokenLanguage {
    static let minimumConfidence = 0.8

    static func of(_ text: String) -> NLLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              confidence >= minimumConfidence else { return nil }
        return language
    }
}

struct MessageLanguageCheck: DecisionConfirming {
    static func hint(for language: NLLanguage) -> String {
        let name = Locale(identifier: "en").localizedString(forLanguageCode: language.rawValue) ?? language.rawValue
        return PromptLibrary.text("check_message_language", ["message_tool": ToolRouter.messageTool,
                                                             "language": name])
    }

    func checked(_ decision: ToolDecision, wish: String,
                 asking ask: (String) async -> ToolDecision?) async -> ToolDecision {
        guard Self.translated(decision, wish: wish), let asked = SpokenLanguage.of(wish) else { return decision }
        flowMark("NACHRICHT sprache weicht ab, frage nach sprache=\(asked.rawValue)")
        guard var answer = await ask(Self.hint(for: asked)), case .message = answer.route else { return decision }
        answer.wish = decision.wish
        let still = Self.translated(answer, wish: wish)
        flowMark("NACHRICHT sprache nachgefragt weicht_ab=\(still)")
        guard still, case .message(var request) = answer.route else { return answer }
        request.needsReview = true
        answer.route = .message(request)
        return answer
    }

    static func translated(_ decision: ToolDecision, wish: String) -> Bool {
        guard case .message(let request) = decision.route,
              let asked = SpokenLanguage.of(wish),
              let written = SpokenLanguage.of(request.text) else { return false }
        return asked != written
    }
}
