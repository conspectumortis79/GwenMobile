import XCTest

enum ToolCallPayload {
    static func message(_ calls: [[String: Any]], content: Any? = nil) -> Data {
        var message: [String: Any] = ["content": content ?? NSNull()]
        if !calls.isEmpty { message["tool_calls"] = calls }
        let body: [String: Any] = ["choices": [["message": message]]]
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }

    static func call(_ name: String, _ arguments: [String: Any]) -> Data {
        message([entry(name, argumentsText(arguments))])
    }

    static func call(_ name: String, _ arguments: String) -> Data {
        message([entry(name, arguments)])
    }

    static func single(_ name: String, _ arguments: String) -> Data {
        message([entry(name, arguments)])
    }

    static func pairs(_ calls: [(String, String)]) -> Data {
        message(calls.enumerated().map { index, pair in
            entry(pair.0, pair.1, id: "c\(index)")
        })
    }

    static func entry(_ name: String, _ arguments: String, id: String = "c1") -> [String: Any] {
        ["id": id, "type": "function", "function": ["name": name, "arguments": arguments]]
    }

    private static func argumentsText(_ arguments: [String: Any]) -> String {
        (try? JSONSerialization.data(withJSONObject: arguments))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}

extension XCTestCase {
    @nonobjc func payload(_ calls: [[String: Any]], _ content: Any? = nil) -> Data {
        ToolCallPayload.message(calls, content: content)
    }

    @nonobjc func payload(_ name: String, _ arguments: String) -> Data {
        ToolCallPayload.single(name, arguments)
    }

    @nonobjc func payload(_ calls: [(String, String)]) -> Data {
        ToolCallPayload.pairs(calls)
    }

    @nonobjc func payload(content: Any?, calls: [[String: Any]] = []) -> Data {
        ToolCallPayload.message(calls, content: content)
    }

    @nonobjc func call(_ name: String, _ arguments: [String: Any]) -> Data {
        ToolCallPayload.call(name, arguments)
    }

    @nonobjc func call(_ name: String, _ arguments: String) -> Data {
        ToolCallPayload.call(name, arguments)
    }
}
