import Foundation

protocol ConversationPersisting: Sendable {
    func persist(_ conversations: [Conversation]) async throws
    func persistNow(_ conversations: [Conversation]) throws
    func load() -> [Conversation]?
}

struct ConversationFilePersistence: ConversationPersisting {
    let url: URL

    func persist(_ conversations: [Conversation]) async throws {
        try await Offload.run { try Self.store(conversations, to: url) }
    }

    func persistNow(_ conversations: [Conversation]) throws {
        try Self.store(conversations, to: url)
    }

    func load() -> [Conversation]? {
        guard let data = try? Data(contentsOf: url),
              let conversations = try? JSONDecoder().decode([Conversation].self, from: data) else { return nil }
        return conversations
    }

    private static func store(_ conversations: [Conversation], to url: URL) throws {
        let data = try JSONEncoder().encode(conversations)
        try data.write(to: url, options: .atomic)
    }
}
