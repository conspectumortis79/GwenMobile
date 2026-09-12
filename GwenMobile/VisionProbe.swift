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
        guard let url = HTTP.endpoint(baseURL, APIEndpoint.chatCompletions) else {
            throw APIError(message: L.t("bad_url"))
        }
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": [["role": "user", "content": [
                ["type": "image_url", "image_url": ["url": imageDataURL]],
                ["type": "text", "text": question],
            ]]],
        ]
        return try HTTP.jsonPOST(url: url, key: key, body: body, timeout: APITimeout.probeRequest)
    }

    static func promptTokenDetails(in data: Data) -> [String: Any]? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = obj["usage"] as? [String: Any] else { return nil }
        return usage["prompt_tokens_details"] as? [String: Any]
    }

    static func imageTokens(in data: Data) -> Int? {
        guard let details = promptTokenDetails(in: data) else { return nil }
        return details["image_tokens"] as? Int
    }

    static func support(response: ProbeResponse?) -> VisionSupport {
        guard let response else { return .unknown }
        guard response.status < 500, !inconclusiveStatuses.contains(response.status) else { return .unknown }
        if response.rejectedByProvider { return .rejected }
        guard promptTokenDetails(in: response.body) != nil else { return .unknown }
        return (imageTokens(in: response.body) ?? 0) > 0 ? .supported : .rejected
    }
}

enum VisionCapabilityProbe {
    static func support(baseURL: String, key: String, model: String) async -> VisionSupport {
        guard let request = try? VisionProbe.request(baseURL: baseURL, key: key, model: model) else {
            return .unknown
        }
        return VisionProbe.support(response: await HTTP.probeResponse(request))
    }
}
