import GwenMobileKit
import Foundation

struct ErrorPayload: Decodable {
    var message: String?
    var code: String?

    enum CodingKeys: String, CodingKey {
        case message, code, detail, msg, reason
    }

    init(from decoder: Decoder) throws {
        if let bare = try? decoder.singleValueContainer().decode(String.self) {
            message = bare.trimmed.nilIfEmpty
            code = nil
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = container.lossyString(.message) ?? container.lossyString(.detail)
            ?? container.lossyString(.msg) ?? container.lossyString(.reason)
        code = container.lossyString(.code)
    }
}

private extension KeyedDecodingContainer {
    func lossyString(_ key: Key) -> String? {
        if let text = try? decodeIfPresent(String.self, forKey: key) { return text.nilIfEmpty }
        if let number = try? decodeIfPresent(Int.self, forKey: key) { return String(number) }
        if let flag = try? decodeIfPresent(Bool.self, forKey: key) { return flag ? "true" : "false" }
        return nil
    }
}

enum APIErrorParser {
    static let detailLimit = 200
    static let sseDataPrefix = "data:"
    static let sseDone = "[DONE]"

    static func message(from data: Data, status: Int) -> String {
        message(from: String(data: data, encoding: .utf8) ?? "", status: status)
    }

    static func message(from body: String, status: Int) -> String {
        detail(of: body) ?? "HTTP \(status)"
    }

    private static func detail(of body: String) -> String? {
        let payload = unwrapped(body)
        guard let data = payload.data(using: .utf8) else { return truncated(payload) }
        if let response = try? JSONDecoder().decode(ChatResponse.self, from: data), let error = response.error {
            return combined(error) ?? error.message
        }
        if let native = try? JSONDecoder().decode(ErrorPayload.self, from: data),
           native.code != nil || native.message != nil {
            return combined(native) ?? native.code ?? native.message
        }
        return truncated(payload)
    }

    private static func unwrapped(_ body: String) -> String {
        let payloads = body.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let text = line.trimmingCharacters(in: .whitespaces)
            guard text.hasPrefix(sseDataPrefix) else { return nil }
            let payload = String(text.dropFirst(sseDataPrefix.count)).trimmingCharacters(in: .whitespaces)
            return payload.isEmpty || payload == sseDone ? nil : payload
        }
        return payloads.isEmpty ? body : payloads.joined(separator: "\n")
    }

    private static func combined(_ payload: ErrorPayload) -> String? {
        guard let code = payload.code, let message = payload.message else { return nil }
        return "\(code): \(message)"
    }

    private static func truncated(_ body: String) -> String? {
        let plain = body.contains("<")
            ? HTMLText.plain(body, hiding: HTMLText.invisibleBlocks)
            : body.trimmed
        return plain.isEmpty ? nil : String(plain.prefix(detailLimit))
    }
}

enum JSONFragment {
    static func data(of text: String) -> Data? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              let slice = String(text[start...end]).data(using: .utf8) else { return nil }
        return slice
    }

    static func decode<Outcome: Decodable>(_ type: Outcome.Type, from text: String?) -> Outcome? {
        guard let text, let data = data(of: text) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func object(from text: String) -> [String: Any]? {
        guard let data = data(of: text),
              let parsed = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return parsed as? [String: Any]
    }
}
