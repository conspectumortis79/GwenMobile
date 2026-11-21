import GwenMobileKit
import Foundation

enum FollowUpResolver {
    static let maxQueryChars = 160
    static let maxTokens = 200

    static func requestMessages(text: String, history: [ChatMessage]) -> [ChatMessage] {
        let context = ConversationTranscript.withoutTheNewestQuestion(from: history)
        return [ChatMessage(role: .user,
                            text: "\(PromptToken.context):\n\(context)\n\n\(PromptToken.newQuestion):\n\(text)")]
    }

    static func resolvedQuery(from data: Data) -> String? {
        guard let raw = ToolRouter.resolvedText(from: data, tool: ToolRouter.resolveQueryTool, field: "query")
        else { return nil }
        return String(raw.prefix(maxQueryChars)).trimmed.nilIfEmpty
    }

    static func isUsable(_ resolved: String, insteadOf original: String) -> Bool {
        let text = resolved.trimmed
        guard text.count >= 8, text.count <= maxQueryChars else { return false }
        return text.lowercased() != original.trimmed.lowercased()
    }

}
