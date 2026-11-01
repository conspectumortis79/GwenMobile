import GwenMobileKit
import Foundation

enum VisionSupport: String, Codable, Sendable {
    case unknown
    case supported
    case rejected

    var isKnown: Bool { self != .unknown }
}

enum VisionProbe {
    static let imageDataURL = "data:image/png;base64,"
        + "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAIAAACQkWg2AAAAFklEQVR42mO4o6FBEmIY1TCqYfhqAAAyBCwQhCQ/2gAAAABJRU5ErkJggg=="
    static let question = "Was ist auf dem Bild?"
    static let maxTokens = 8
    static let inconclusiveStatuses: Set<Int> = [401, 403, 404, 408, 429]

    static func request(baseURL: String, key: String, model: String) throws -> URLRequest {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": [ChatPayload.user([ChatPayload.image(url: imageDataURL),
                                           ChatPayload.text(question)])],
        ]
        return try HTTP.jsonPOST(url: HTTP.chatCompletionsURL(baseURL), key: key, body: body,
                                 timeout: APITimeout.probeRequest)
    }

    static func promptTokenDetails(in data: Data) -> [String: Any]? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = obj["usage"] as? [String: Any] else { return nil }
        return usage["prompt_tokens_details"] as? [String: Any]
    }

    static func support(response: ProbeResponse?, requiresImageTokens: Bool = true) -> VisionSupport {
        guard let response else { return .unknown }
        guard response.status < 500, !inconclusiveStatuses.contains(response.status) else { return .unknown }
        if response.rejectedByProvider { return .rejected }
        guard let details = promptTokenDetails(in: response.body) else {
            return requiresImageTokens ? .unknown : acceptedWithoutDetails(response.body)
        }
        guard let tokens = details["image_tokens"] as? Int else {
            return requiresImageTokens ? .rejected : .supported
        }
        return tokens > 0 ? .supported : .rejected
    }

    private static func acceptedWithoutDetails(_ body: Data) -> VisionSupport {
        (try? JSONSerialization.jsonObject(with: body)) is [String: Any] ? .supported : .unknown
    }
}

enum VisionCapabilityProbe {
    static func support(baseURL: String, key: String, model: String,
                        requiresImageTokens: Bool = true) async -> VisionSupport {
        guard let request = try? VisionProbe.request(baseURL: baseURL, key: key, model: model) else {
            return .unknown
        }
        return VisionProbe.support(response: await HTTP.probeResponse(request),
                                   requiresImageTokens: requiresImageTokens)
    }
}
