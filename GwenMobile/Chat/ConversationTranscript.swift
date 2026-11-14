import GwenMobileKit
import Foundation

enum ConversationTranscript {
    static let defaultLimit = 6
    static let defaultCap = 400
    static let defaultAnswerCap = 6000

    enum Picture: String {
        case attached = "image attached"
        case generated = "generated image"
    }

    static func from(messages: [ChatMessage],
                     limit: Int = defaultLimit,
                     cap: Int = defaultCap,
                     answerCap: Int = defaultAnswerCap) -> String {
        let window = Array(messages.suffix(limit))
        let latestAnswer = window.lastIndex { $0.role == .assistant }
        return window.indices.map { index in
            let message = window[index]
            let room = index == latestAnswer ? max(cap, answerCap) : cap
            let body = String(message.text.prefix(room)).replacingOccurrences(of: "\n", with: " ")
            return "\(message.role == .user ? "user" : "assistant"): \(body)\(pictureHint(for: message))"
        }.joined(separator: "\n")
    }

    static func pictureHint(for message: ChatMessage) -> String {
        var hints: [String] = []
        if !message.images.isEmpty { hints.append(Picture.attached.rawValue) }
        if message.outImages?.isEmpty == false { hints.append(Picture.generated.rawValue) }
        return hints.isEmpty ? "" : " [\(hints.joined(separator: ", "))]"
    }

    static func historyWithoutNewestQuestion(_ messages: [ChatMessage]) -> [ChatMessage] {
        guard let newest = messages.lastIndex(where: { $0.role == .user }) else { return [] }
        var kept = messages
        kept.remove(at: newest)
        return kept
    }

    static func withoutTheNewestQuestion(from messages: [ChatMessage]) -> String {
        from(messages: historyWithoutNewestQuestion(messages))
    }
}
