@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import Foundation

extension ToolCall {
    var parsedArguments: [String: Any]? {
        guard let data = arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }
}

enum ToolProbeOutcome: Equatable {
    case rejected(status: Int, message: String)
    case acceptedWithoutCall(text: String)
    case called([ToolCall])

    var summary: String {
        switch self {
        case .rejected(let status, let message): return "abgelehnt status=\(status) text=\(message.prefix(90))"
        case .acceptedWithoutCall(let text): return "akzeptiert ohne_call=ja text=\(text.prefix(60))"
        case .called(let calls): return "calls=\(calls.count) namen=\(calls.map(\.name).joined(separator: ","))"
        }
    }
}

enum ToolCapabilityProbe {
    static let toolName = "gwen_probe_calendar_intent"
    static let secondToolName = "gwen_probe_web_lookup"
    static let maxTokens = 120
    static let question = "Trag bitte morgen um 14 Uhr einen Zahnarzttermin für eine Stunde ein."

    static func tools() -> [[String: Any]] {
        [
            ["type": "function",
             "function": [
                "name": toolName,
                "description": "Creates a calendar appointment in the user's calendar.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string"],
                        "start": ["type": "string", "description": "Local start time as YYYY-MM-DD HH:MM"],
                        "minutes": ["type": "integer"],
                    ],
                    "required": ["title", "start"],
                ],
             ]],
            ["type": "function",
             "function": [
                "name": secondToolName,
                "description": "Looks something up on the web.",
                "parameters": ["type": "object", "properties": ["query": ["type": "string"]],
                               "required": ["query"]],
             ]],
        ]
    }

    static func request(baseURL: String, key: String, model: String, toolChoice: Any = "auto",
                        stream: Bool = false, withDate: Bool = false,
                        extra: [String: Any] = [:]) throws -> URLRequest {
        var messages: [[String: Any]] = []
        if withDate {
            messages.append(["role": "system",
                             "content": "Current date: \(Formatters.systemDate(Date())). "
                             + "Times you output are local, 24h."])
        }
        messages.append(["role": "user", "content": question])
        var body = ToolRouter.toolRequestBody(model: model, maxTokens: maxTokens, stream: stream,
                                             messages: messages, tools: tools(),
                                             toolChoice: toolChoice)
        body.merge(extra) { _, new in new }
        return try HTTP.jsonPOST(url: HTTP.chatCompletionsURL(baseURL), key: key, body: body,
                                 timeout: APITimeout.toolProbeRequest)
    }

    static func echoRequest(baseURL: String, key: String, model: String, call: ToolCall,
                            extra: [String: Any] = [:]) throws -> URLRequest {
        let messages: [[String: Any]] = [
            ["role": "user", "content": question],
            ["role": "assistant", "content": NSNull(),
             "tool_calls": [["id": "probe_call_1", "type": "function",
                             "function": ["name": call.name, "arguments": call.arguments]]]],
            ["role": "tool", "tool_call_id": "probe_call_1", "name": call.name,
             "content": "{\"ok\":true,\"summary\":\"Termin morgen 14:00 bis 15:00 angelegt\"}"],
        ]
        var body = ToolRouter.toolRequestBody(model: model, maxTokens: maxTokens, stream: false,
                                             messages: messages, tools: tools())
        body.merge(extra) { _, new in new }
        return try HTTP.jsonPOST(url: HTTP.chatCompletionsURL(baseURL), key: key, body: body,
                                 timeout: APITimeout.toolProbeRequest)
    }

    static func outcome(data: Data, status: Int) -> ToolProbeOutcome {
        guard status < 400 else {
            return .rejected(status: status, message: APIErrorParser.message(from: data, status: status))
        }
        guard let found = ToolRouter.firstChoice(from: data) else {
            return .rejected(status: status, message: "keine choices im Antwortkörper")
        }
        if let calls = found.message["tool_calls"] as? [[String: Any]], !calls.isEmpty {
            return .called(calls.compactMap { raw -> ToolCall? in
                guard let function = raw["function"] as? [String: Any],
                      let name = function["name"] as? String else { return nil }
                return ToolCall(name: name, arguments: function["arguments"] as? String ?? "")
            })
        }
        return .acceptedWithoutCall(text: (found.message["content"] as? String) ?? "")
    }

    static func reasoningCharacters(in data: Data) -> Int {
        (ToolRouter.firstChoice(from: data)?.message["reasoning_content"] as? String)?.count ?? 0
    }

    static func streamCarriesToolCalls(_ lines: [String]) -> Bool {
        lines.contains { $0.contains("\"tool_calls\"") && $0.contains("\"function\"") }
    }
}
#endif
