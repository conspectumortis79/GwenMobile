import Foundation

struct ModelTurn {
    var messages: [ChatMessage]
    var images: [Data]

    var needsVision: Bool { !images.isEmpty }
}

enum ConversationMemory {
    static let maxMessages = 30

    static func turn(from messages: [ChatMessage], load: (Attachment) -> Data?) -> ModelTurn {
        var window = window(from: messages)
        var bytes: [Data] = []
        for index in window.indices {
            var usable: [Attachment] = []
            for attachment in window[index].images {
                guard let data = load(attachment) else { continue }
                usable.append(attachment)
                bytes.append(data)
            }
            window[index].images = usable
        }
        return ModelTurn(messages: window, images: bytes)
    }

    static func rememberedImages(from messages: [ChatMessage]) -> [Attachment] {
        window(from: messages).flatMap(\.images)
    }

    static func window(from messages: [ChatMessage]) -> [ChatMessage] {
        var window = Array(messages.suffix(maxMessages))
        guard let speaker = window.indices.last(where: { window[$0].role == .user }) else {
            return window.map(cleared)
        }
        switch newestPicture(in: window) {
        case .none:
            window[speaker].images = []
        case .attached(let index):
            for position in window.indices where position != index { window[position].images = [] }
        case .generated(let pictures):
            for position in window.indices where position != speaker { window[position].images = [] }
            window[speaker].images = pictures
        }
        return window
    }

    private enum Picture {
        case attached(Int)
        case generated([Attachment])
    }

    private static func newestPicture(in window: [ChatMessage]) -> Picture? {
        for index in window.indices.reversed() {
            let message = window[index]
            if message.role == .user {
                if !message.images.isEmpty { return .attached(index) }
            } else if let output = message.outImages, !output.isEmpty {
                return .generated(output)
            }
        }
        return nil
    }

    private static func cleared(_ message: ChatMessage) -> ChatMessage {
        guard !message.images.isEmpty else { return message }
        var copy = message
        copy.images = []
        return copy
    }
}
