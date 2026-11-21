@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit
@testable import GwenMobileProbes

final class ToolCapabilityProbeTests: XCTestCase {
    private func json(_ text: String) -> Data { Data(text.utf8) }

    private let accepted = """
    {"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[\
    {"id":"call_1","type":"function","function":{"name":"gwen_probe_calendar_intent",\
    "arguments":"{\\"title\\":\\"Zahnarzt\\",\\"start\\":\\"2026-09-13 14:00\\",\\"minutes\\":60}"}}]}}]}
    """

    func testToolCallsAreReadOutOfTheMessage() throws {
        guard case .called(let calls) = ToolCapabilityProbe.outcome(data: json(accepted), status: 200) else {
            return XCTFail("tool_calls wurden nicht erkannt")
        }
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.name, ToolCapabilityProbe.toolName)
        XCTAssertEqual(calls.first?.parsedArguments?["title"] as? String, "Zahnarzt")
        XCTAssertEqual(calls.first?.parsedArguments?["minutes"] as? Int, 60)
    }

    func testPlainAnswerCountsAsAcceptedWithoutCall() {
        let data = json(#"{"choices":[{"message":{"role":"assistant","content":"Das mache ich."}}]}"#)
        guard case .acceptedWithoutCall(let text) = ToolCapabilityProbe.outcome(data: data, status: 200) else {
            return XCTFail("Textantwort musste als ohne Call zählen")
        }
        XCTAssertEqual(text, "Das mache ich.")
    }

    func testBrokenArgumentsStayRawAndMarkedUnparseable() {
        let data = json(#"{"choices":[{"message":{"tool_calls":[{"function":{"name":"x","arguments":"{title"}}]}}]}"#)
        guard case .called(let calls) = ToolCapabilityProbe.outcome(data: data, status: 200) else {
            return XCTFail("Call musste erkannt werden")
        }
        XCTAssertEqual(calls.first?.arguments, "{title")
        XCTAssertNil(calls.first?.parsedArguments)
    }

    func testRejectedStatusKeepsProviderMessage() {
        let data = json(#"{"error":{"message":"'tools' is not supported for this model"}}"#)
        guard case .rejected(let status, let message) = ToolCapabilityProbe.outcome(data: data, status: 400) else {
            return XCTFail("Ablehnung musste als Ablehnung ankommen")
        }
        XCTAssertEqual(status, 400)
        XCTAssertTrue(message.contains("not supported"))
    }

    func testStreamDeltasAreDetectedByToolCallFragment() {
        XCTAssertFalse(ToolCapabilityProbe.streamCarriesToolCalls(["data: {\"choices\":[{\"delta\":{\"content\":\"hallo\"}}]}"]))
        XCTAssertTrue(ToolCapabilityProbe.streamCarriesToolCalls(
            ["data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"function\":{\"name\":\"x\"}}]}}]}"]))
    }

    func testRequestCarriesToolSchemaAndChoice() throws {
        let req = try ToolCapabilityProbe.request(baseURL: "https://api.test/v1", key: "sk-x",
                                                  model: "qwen3.8-flash", toolChoice: "required")
        let body = try XCTUnwrap(jsonBody(of: req))
        XCTAssertEqual(req.url?.path.hasSuffix("/chat/completions"), true)
        XCTAssertEqual(body["tool_choice"] as? String, "required")
        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 2)
        let function = try XCTUnwrap(tools.first?["function"] as? [String: Any])
        XCTAssertEqual(function["name"] as? String, ToolCapabilityProbe.toolName)
        let parameters = try XCTUnwrap(function["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["required"] as? [String], ["title", "start"])
    }

    func testEchoRoundTripSendsAssistantCallAndToolResult() throws {
        let req = try ToolCapabilityProbe.echoRequest(baseURL: "https://api.test/v1", key: "sk-x",
                                                      model: "m", call: ToolCall(name: "x", arguments: "{}"))
        let body = try XCTUnwrap(jsonBody(of: req))
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 3)
        XCTAssertEqual(messages[1]["role"] as? String, "assistant")
        XCTAssertNotNil(messages[1]["tool_calls"])
        XCTAssertEqual(messages[2]["role"] as? String, "tool")
        XCTAssertEqual(messages[2]["tool_call_id"] as? String, "probe_call_1")
        XCTAssertNil(body["reasoning_effort"])
    }

    func testTheEchoRoundCarriesTheThinkingSwitchOfTheApp() throws {
        let req = try ToolCapabilityProbe.echoRequest(baseURL: "https://api.test/v1", key: "sk-x", model: "m",
                                                      call: ToolCall(name: "x", arguments: "{}"),
                                                      extra: ["reasoning_effort": "none"])
        let body = try XCTUnwrap(jsonBody(of: req))
        XCTAssertEqual(body["reasoning_effort"] as? String, "none")
        XCTAssertEqual((body["messages"] as? [[String: Any]])?.count, 3)
    }

    func testTheReasoningLengthIsReadOutOfTheMessage() {
        let thought = json(#"{"choices":[{"finish_reason":"length","message":{"content":"","#
                           + #""reasoning_content":"Erst denken"}}]}"#)
        XCTAssertEqual(ToolCapabilityProbe.reasoningCharacters(in: thought), 11)
        XCTAssertEqual(ToolCapabilityProbe.reasoningCharacters(in: json(accepted)), 0)
        XCTAssertEqual(ToolCapabilityProbe.reasoningCharacters(in: json("{}")), 0)
    }
}
