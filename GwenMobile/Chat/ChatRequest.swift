import GwenMobileKit
import Foundation

enum ChatPayload {
    static func message(role: Role, content: Any) -> [String: Any] {
        ["role": role.rawValue, "content": content]
    }

    static func system(_ text: String) -> [String: Any] {
        ["role": "system", "content": text]
    }

    static func user(_ content: Any) -> [String: Any] {
        message(role: .user, content: content)
    }

    static func text(_ text: String) -> [String: Any] {
        ["type": "text", "text": text]
    }

    static func image(_ data: Data) -> [String: Any]? {
        guard let url = QwenAPI.dataURL(data) else { return nil }
        return image(url: url)
    }

    static func image(url: String) -> [String: Any] {
        ["type": "image_url", "image_url": ["url": url]]
    }

    static func video(_ data: Data) -> [String: Any] {
        let mime = VideoBytes.mimeType(data)
        let url = "data:\(mime);base64,\(data.base64EncodedString())"
        return video(url: url)
    }

    static func video(url: String) -> [String: Any] {
        ["type": "video_url", "video_url": ["url": url], "fps": 2]
    }
}

enum ChatRequest {
    static func post(baseURL: String, key: String, model: String, messages: [[String: Any]],
                     stream: Bool, thinking: ThinkingDirective, timeout: TimeInterval,
                     temperature: Double? = nil,
                     accept: String? = nil, extra: [String: Any] = [:]) throws -> URLRequest {
        var body: [String: Any] = ["model": model, "messages": messages, "stream": stream]
        for (key, value) in extra { body[key] = value }
        if let temperature { body["temperature"] = temperature }
        thinking.applied(to: &body)
        return try HTTP.jsonPOST(url: HTTP.chatCompletionsURL(baseURL), key: key, body: body,
                                 timeout: timeout, accept: accept)
    }
}
