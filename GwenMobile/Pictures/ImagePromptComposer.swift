import GwenMobileKit
import Foundation

enum ImagePromptComposer {
    static let minPromptChars = 12
    static let maxPromptChars = 600
    static let maxTokens = 400

    static func requestMessages(text: String, history: [ChatMessage]) -> [ChatMessage] {
        FollowUpResolver.requestMessages(text: text, history: history)
    }

    static func prompt(from data: Data) -> String? {
        guard let object = ToolRouter.arguments(from: data, named: ToolRouter.composeImagePromptTool),
              object["status"] as? String == StructuredToolStatus.resolved.rawValue,
              let raw = object["prompt"] as? String else { return nil }
        let prompt = raw.trimmed
        return prompt.isEmpty ? nil : prompt
    }

    static func usablePrompt(_ raw: String?, insteadOf text: String) -> String? {
        guard let raw else { return nil }
        let prompt = raw.trimmed
        let original = text.trimmed
        guard prompt.count >= minPromptChars else { return nil }
        guard prompt.lowercased() != original.lowercased() else { return nil }
        return String(prompt.prefix(maxPromptChars))
    }
}
