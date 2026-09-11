import Foundation

enum ConversationTranscript {
    static let defaultLimit = 6
    static let defaultCap = 400

    enum Picture: String {
        case attached = "image attached"
        case generated = "generated image"
    }

    static func from(messages: [ChatMessage],
                     limit: Int = defaultLimit,
                     cap: Int = defaultCap) -> String {
        messages.suffix(limit).map { message in
            let body = String(message.text.prefix(cap)).replacingOccurrences(of: "\n", with: " ")
            return "\(message.role == .user ? "user" : "assistant"): \(body)\(pictureHint(for: message))"
        }.joined(separator: "\n")
    }

    static func pictureHint(for message: ChatMessage) -> String {
        var hints: [String] = []
        if !message.images.isEmpty { hints.append(Picture.attached.rawValue) }
        if message.outImages?.isEmpty == false { hints.append(Picture.generated.rawValue) }
        return hints.isEmpty ? "" : " [\(hints.joined(separator: ", "))]"
    }

    static func withoutTheNewestQuestion(from messages: [ChatMessage]) -> String {
        from(messages: Array(messages.dropLast()))
    }
}
