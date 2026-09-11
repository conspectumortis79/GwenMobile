import Foundation

enum ThinkingProbe {
    static let invalidLevelValue = "__gwen_sonde__"
    static let prompt = "OK"
    static let maxTokens = 8

    static func levelRequest(baseURL: String, key: String, model: String) throws -> URLRequest {
        try probeRequest(baseURL: baseURL, key: key, model: model,
                         extra: ["reasoning_effort": invalidLevelValue])
    }

    static func switchOffRequest(baseURL: String, key: String, model: String) throws -> URLRequest {
        try probeRequest(baseURL: baseURL, key: key, model: model,
                         extra: ["enable_thinking": false])
    }

    private static func probeRequest(baseURL: String, key: String, model: String,
                                     extra: [String: Any]) throws -> URLRequest {
        guard let url = HTTP.endpoint(baseURL, APIEndpoint.chatCompletions) else {
            throw APIError(message: L.t("bad_url"))
        }
        var body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": maxTokens,
        ]
        body.merge(extra) { _, new in new }
        return try HTTP.jsonPOST(url: url, key: key, body: body, timeout: APITimeout.probeRequest)
    }

    static func message(from data: Data) -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        if let direct = obj["message"] as? String, !direct.isEmpty { return direct }
        if let error = obj["error"] as? [String: Any], let nested = error["message"] as? String {
            return nested
        }
        return ""
    }

    static func levels(in message: String) -> [ThinkingLevel] {
        guard let marker = message.range(of: "must be one of:") else { return [] }
        let tail = message[marker.upperBound...].split(separator: "\"").first.map(String.init) ?? ""
        var found: [ThinkingLevel] = []
        for token in tail.split(whereSeparator: { $0 == "," || $0 == "'" || $0 == " " || $0 == ":" }) {
            guard let level = ThinkingLevel(rawValue: String(token)), !found.contains(level) else { continue }
            found.append(level)
        }
        return found
    }

    static func reasoningText(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else { return nil }
        return message["reasoning_content"] as? String
    }
}

enum ThinkingCapabilityProbe {
    static func capabilities(baseURL: String, key: String, model: String) async -> ThinkingCapabilities {
        var caps = ThinkingCapabilities()
        if let request = try? ThinkingProbe.levelRequest(baseURL: baseURL, key: key, model: model),
           let response = await HTTP.probeResponse(request) {
            caps.levels = ThinkingProbe.levels(in: ThinkingProbe.message(from: response.body))
        }
        if let request = try? ThinkingProbe.switchOffRequest(baseURL: baseURL, key: key, model: model),
           let response = await HTTP.probeResponse(request), response.succeeded,
           (ThinkingProbe.reasoningText(from: response.body) ?? "").isEmpty {
            caps.canSwitchOff = true
        }
        return caps
    }
}
