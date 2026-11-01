import GwenMobileKit
import Foundation
import MLXLMCommon

struct LocalToolCall: Equatable, Sendable {
    var id: String
    var name: String
    var arguments: String
}

struct LocalChatResult: Equatable, Sendable {
    var text: String
    var toolCalls: [LocalToolCall]
    var promptTokens: Int
    var completionTokens: Int
    var finishReason: String
}

enum LocalOpenAIResponse {
    static let identifier = "chatcmpl-local"

    static func models(_ ids: [String]) -> Data {
        let data: [String: Any] = [
            "object": "list",
            "data": ids.sorted().map { ["id": $0, "object": "model", "owned_by": "local"] },
        ]
        return (try? JSONSerialization.data(withJSONObject: data, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    static func completion(model: String, result: LocalChatResult) -> Data {
        var message: [String: Any] = ["role": "assistant", "content": result.text]
        if !result.toolCalls.isEmpty {
            message["tool_calls"] = result.toolCalls.map(toolCall)
        }
        let body: [String: Any] = [
            "id": identifier,
            "object": "chat.completion",
            "created": Int(Date().timeIntervalSince1970),
            "model": model,
            "choices": [[
                "index": 0,
                "message": message,
                "finish_reason": result.finishReason,
            ]],
            "usage": usage(result),
        ]
        return (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]))
            ?? error(LocalRequestError.empty.localizedDescription)
    }

    static func chunk(model: String, text: String) -> String {
        let body: [String: Any] = [
            "id": identifier,
            "object": "chat.completion.chunk",
            "created": Int(Date().timeIntervalSince1970),
            "model": model,
            "choices": [[
                "index": 0,
                "delta": ["content": text],
                "finish_reason": NSNull(),
            ]],
        ]
        return sse(body)
    }

    static func toolChunk(model: String, call: LocalToolCall, index: Int) -> String {
        let body: [String: Any] = [
            "id": identifier,
            "object": "chat.completion.chunk",
            "created": Int(Date().timeIntervalSince1970),
            "model": model,
            "choices": [[
                "index": 0,
                "delta": ["tool_calls": [[
                    "index": index,
                    "id": call.id,
                    "type": "function",
                    "function": ["name": call.name, "arguments": call.arguments],
                ]]],
                "finish_reason": NSNull(),
            ]],
        ]
        return sse(body)
    }

    static func finalChunk(model: String, reason: String) -> String {
        let body: [String: Any] = [
            "id": identifier,
            "object": "chat.completion.chunk",
            "created": Int(Date().timeIntervalSince1970),
            "model": model,
            "choices": [[
                "index": 0,
                "delta": [:] as [String: Any],
                "finish_reason": reason,
            ]],
        ]
        return sse(body)
    }

    static func done() -> String {
        "data: [DONE]\n\n"
    }

    static func error(_ message: String) -> Data {
        let body: [String: Any] = ["error": ["message": message, "type": "local_error"]]
        return (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]))
            ?? Data("{\"error\":{\"message\":\"local\"}}".utf8)
    }

    static func toolCall(_ call: MLXLMCommon.ToolCall, index: Int) -> LocalToolCall {
        let arguments = (try? JSONEncoder().encode(call.function.arguments))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return LocalToolCall(id: call.id ?? "call_local_\(index)",
                             name: call.function.name,
                             arguments: arguments)
    }

    private static func usage(_ result: LocalChatResult) -> [String: Any] {
        [
            "prompt_tokens": result.promptTokens,
            "completion_tokens": result.completionTokens,
            "total_tokens": result.promptTokens + result.completionTokens,
        ]
    }

    private static func toolCall(_ call: LocalToolCall) -> [String: Any] {
        [
            "id": call.id,
            "type": "function",
            "function": ["name": call.name, "arguments": call.arguments],
        ]
    }

    private static func sse(_ body: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]))
            ?? Data("{}".utf8)
        return "data: " + (String(data: data, encoding: .utf8) ?? "{}") + "\n\n"
    }
}
