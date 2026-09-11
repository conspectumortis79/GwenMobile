import Foundation

struct MessagePart: Decodable {
    var image: String?
    var text: String?
}

struct ChatResponse: Decodable {
    struct Message: Decodable {
        var role: String?
        var text: String?
        var parts: [MessagePart]?

        private enum CodingKeys: String, CodingKey {
            case role
            case content
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            role = try container.decodeIfPresent(String.self, forKey: .role)
            if let plain = try? container.decode(String.self, forKey: .content) {
                text = plain
                parts = nil
                return
            }
            text = nil
            parts = try container.decodeIfPresent([MessagePart].self, forKey: .content)
        }
    }

    struct Choice: Decodable {
        struct Delta: Decodable { var content: String? }
        var delta: Delta?
        var message: Message?
    }

    struct Envelope: Decodable { var choices: [Choice]? }

    var choices: [Choice]?
    var output: Envelope?
    var error: ErrorPayload?

    var streamChunk: String? { choices?.first?.delta?.content }
    var answerText: String? { firstMessage?.text }
    var answerParts: [MessagePart]? { firstMessage?.parts }

    private var firstMessage: Message? { choices?.first?.message ?? output?.choices?.first?.message }
}
