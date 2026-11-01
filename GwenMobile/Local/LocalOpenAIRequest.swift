import GwenMobileKit
import CoreFoundation
import Foundation
import MLXLMCommon

enum LocalRole: String, Sendable {
    case system
    case user
    case assistant
    case tool
}

struct LocalMessage: Equatable, Sendable {
    var role: LocalRole
    var text: String
    var images: [Data]

    init(role: LocalRole, text: String, images: [Data] = []) {
        self.role = role
        self.text = text
        self.images = images
    }
}

enum LocalRequestError: LocalizedError {
    case empty
    case noModel
    case noQuestion
    case badImage
    case remoteImage

    var errorDescription: String? {
        switch self {
        case .empty: return L.t("local_error_empty")
        case .noModel: return L.t("local_error_model")
        case .noQuestion: return L.t("local_error_question")
        case .badImage: return L.t("local_error_image")
        case .remoteImage: return L.t("local_error_remote_image")
        }
    }
}

struct LocalChatRequest: Sendable {
    var model: String
    var messages: [LocalMessage]
    var tools: [ToolSpec]
    var maxTokens: Int?
    var thinking: Bool
    var temperature: Float?

    static func parse(_ data: Data) throws -> LocalChatRequest {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LocalRequestError.empty
        }
        guard let model = object["model"] as? String, !model.trimmed.isEmpty else {
            throw LocalRequestError.noModel
        }
        guard let rawMessages = object["messages"] as? [[String: Any]] else {
            throw LocalRequestError.noQuestion
        }
        let messages = try rawMessages.map(parseMessage)
        guard let last = messages.last, last.role == .user else {
            throw LocalRequestError.noQuestion
        }
        var tools: [ToolSpec] = []
        if let rawTools = object["tools"] as? [[String: Any]] {
            tools = rawTools.compactMap { LocalJSON.sendable($0) as? [String: any Sendable] }
        }
        let maxTokens = (object["max_tokens"] as? NSNumber)?.intValue
            ?? (object["max_completion_tokens"] as? NSNumber)?.intValue
        let temperature = (object["temperature"] as? NSNumber)?.floatValue
        return LocalChatRequest(model: model, messages: messages, tools: tools, maxTokens: maxTokens,
                                thinking: thinking(object), temperature: temperature)
    }

    private static func thinking(_ object: [String: Any]) -> Bool {
        if let enabled = object["enable_thinking"] as? Bool { return enabled }
        guard let effort = object["reasoning_effort"] as? String else { return false }
        return effort.lowercased() != "none" && effort.lowercased() != "off"
    }

    private static func parseMessage(_ raw: [String: Any]) throws -> LocalMessage {
        let role = LocalRole(rawValue: raw["role"] as? String ?? "") ?? .user
        guard let content = raw["content"] else {
            return LocalMessage(role: role, text: "")
        }
        if let text = content as? String {
            return LocalMessage(role: role, text: text)
        }
        guard let parts = content as? [[String: Any]] else {
            return LocalMessage(role: role, text: "")
        }
        var text: [String] = []
        var images: [Data] = []
        for part in parts {
            let type = part["type"] as? String ?? ""
            if type == "text" || type == "input_text" {
                if let value = part["text"] as? String { text.append(value) }
            } else if type == "image_url" || type == "input_image" {
                let url = (part["image_url"] as? [String: Any])?["url"] as? String
                    ?? part["image_url"] as? String
                    ?? part["url"] as? String
                if let url, let data = decodeImage(url) {
                    images.append(data)
                } else if let url, url.hasPrefix("http") {
                    throw LocalRequestError.remoteImage
                } else {
                    throw LocalRequestError.badImage
                }
            }
        }
        return LocalMessage(role: role, text: text.joined(separator: "\n"), images: images)
    }

    private static func decodeImage(_ url: String) -> Data? {
        guard url.hasPrefix("data:"), let comma = url.firstIndex(of: ",") else { return nil }
        let payload = String(url[url.index(after: comma)...])
        return Data(base64Encoded: payload, options: .ignoreUnknownCharacters)
    }
}

enum LocalJSON {
    static func sendable(_ value: Any) -> (any Sendable)? {
        if let value = value as? String { return value }
        if let value = value as? Bool { return value }
        if let value = value as? Int { return value }
        if let value = value as? Double { return value }
        if let value = value as? NSNumber {
            if CFGetTypeID(value) == CFBooleanGetTypeID() { return value.boolValue }
            let double = value.doubleValue
            if double.rounded() == double, double >= Double(Int.min), double <= Double(Int.max) {
                return value.intValue
            }
            return double
        }
        if let value = value as? [Any] {
            return value.compactMap(sendable) as [any Sendable]
        }
        if let value = value as? [String: Any] {
            var result: [String: any Sendable] = [:]
            for (key, item) in value {
                if let converted = sendable(item) { result[key] = converted }
            }
            return result
        }
        return nil
    }
}
