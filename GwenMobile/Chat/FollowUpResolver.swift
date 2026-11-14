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
        guard let object = ToolRouter.arguments(from: data, named: ToolRouter.resolveQueryTool),
              object["status"] as? String == StructuredToolStatus.resolved.rawValue,
              let raw = object["query"] as? String else { return nil }
        let query = String(raw.trimmed.prefix(maxQueryChars)).trimmed
        return query.isEmpty ? nil : query
    }

    static func isUsable(_ resolved: String, insteadOf original: String) -> Bool {
        let text = resolved.trimmed
        guard text.count >= 8, text.count <= maxQueryChars else { return false }
        return text.lowercased() != original.trimmed.lowercased()
    }

}
