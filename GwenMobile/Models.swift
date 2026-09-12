import Foundation

enum Role: String, Codable {
    case user
    case assistant
}

struct Attachment: Codable, Hashable {
    var file: String
}

struct WebSource: Codable, Hashable {
    var title: String
    var url: String
    var domain: String
}

struct ChatMessage: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var role: Role
    var text: String
    var images: [Attachment] = []
    var date: Date = Date()
    var model: String? = nil
    var elapsed: Double? = nil
    var outImages: [Attachment]? = nil
    var sources: [WebSource]? = nil
    var thinking: ThinkingLevel? = nil
}

extension ChatMessage {
    var pictures: [Attachment] { images + (outImages ?? []) }
    var imageFiles: [String] { pictures.map(\.file) }
}

struct Conversation: Identifiable, Codable {
    var id: UUID = UUID()
    var title: String
    var messages: [ChatMessage] = []
    var updatedAt: Date = Date()
}
