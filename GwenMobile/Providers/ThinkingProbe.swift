import GwenMobileKit
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
        var body: [String: Any] = [
            "model": model,
            "messages": [ChatPayload.user(prompt)],
            "max_tokens": maxTokens,
        ]
        for (key, value) in extra { body[key] = value }
        return try HTTP.jsonPOST(url: HTTP.chatCompletionsURL(baseURL), key: key, body: body,
                                 timeout: APITimeout.probeRequest)
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

    static let valueMarkers = ["one of", "supported values", "allowed values", "valid values", "must be", "expected"]
    static let denialMarkers = ["not supported", "unsupported", "unrecognized", "unknown parameter", "unknown argument",
                                "not permitted", "does not support"]

    static func levelTokens(in message: String) -> [ThinkingLevel] {
        let lower = message.lowercased()
        guard lower.contains("reasoning_effort") || lower.contains(invalidLevelValue) else { return [] }
        var scope = lower
        if let marker = valueMarkers.compactMap({ lower.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) {
            scope = String(lower[marker.upperBound...])
        }
        var found: [ThinkingLevel] = []
        for token in scope.split(whereSeparator: { !$0.isLetter }) {
            guard let level = ThinkingLevel(rawValue: String(token)), level != .modelDefault,
                  !found.contains(level) else { continue }
            found.append(level)
        }
        return found
    }

    static func deniesParameter(_ message: String) -> Bool {
        let lower = message.lowercased()
        guard lower.contains("reasoning_effort") || lower.contains("reasoning") else { return false }
        return denialMarkers.contains { lower.contains($0) }
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

enum OpenAIThinkingProbe {
    static func capabilities(baseURL: String, key: String, model: String) async -> ThinkingCapabilities {
        guard let request = try? ThinkingProbe.levelRequest(baseURL: baseURL, key: key, model: model),
              let response = await HTTP.probeResponse(request) else {
            return ThinkingCapabilities(encoding: .openAI)
        }
        return interpret(response)
    }

    static func interpret(_ response: ProbeResponse) -> ThinkingCapabilities {
        var caps = ThinkingCapabilities(encoding: .openAI)
        guard response.status < 500, !VisionProbe.inconclusiveStatuses.contains(response.status),
              response.rejectedByProvider else { return caps }
        let message = ThinkingProbe.message(from: response.body)
        let levels = ThinkingProbe.levelTokens(in: message)
        if !levels.isEmpty {
            caps.levels = levels
            caps.canSwitchOff = levels.contains(.off)
            caps.probed = true
        } else if ThinkingProbe.deniesParameter(message) {
            caps.probed = true
        }
        return caps
    }
}
