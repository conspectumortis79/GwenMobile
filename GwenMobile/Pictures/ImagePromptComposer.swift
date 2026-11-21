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
        ToolRouter.resolvedText(from: data, tool: ToolRouter.composeImagePromptTool, field: "prompt")
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
