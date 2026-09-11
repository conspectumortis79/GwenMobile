import XCTest
@testable import GwenMobile

final class ThinkingProbeTests: XCTestCase {
    private let flashMessage = "'reasoning_effort' must be one of: 'none', 'minimal', 'low', "
        + "'medium', 'high', 'xhigh', 'max'"
    private let proMessage = "'reasoning_effort' must be one of: 'low', 'medium', 'high', 'xhigh', 'max'"

    private func body(of req: URLRequest) -> [String: Any]? {
        guard let data = req.httpBody else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func data(_ text: String) -> Data { Data(text.utf8) }

    func testLevelListComesOutOfTheProviderSentence() {
        XCTAssertEqual(ThinkingProbe.levels(in: flashMessage),
                       [.off, .minimal, .low, .medium, .high, .xhigh, .max])
        XCTAssertEqual(ThinkingProbe.levels(in: proMessage), [.low, .medium, .high, .xhigh, .max])
    }

    func testUnknownFutureLevelsAreIgnoredInsteadOfGuessed() {
        let message = "'reasoning_effort' must be one of: 'none', 'ultra', 'low'"
        XCTAssertEqual(ThinkingProbe.levels(in: message), [.off, .low])
    }

    func testSentencesWithoutTheMarkerYieldNothing() {
        XCTAssertEqual(ThinkingProbe.levels(in: ""), [])
        XCTAssertEqual(ThinkingProbe.levels(in: "The thinking_budget parameter must be a positive integer"), [])
    }

    func testTrailingJsonNoiseBehindTheListIsCut() {
        let noisy = flashMessage + ",\",\"type\":\"invalid_request_error\"}"
        XCTAssertEqual(ThinkingProbe.levels(in: noisy),
                       [.off, .minimal, .low, .medium, .high, .xhigh, .max])
    }

    func testBothErrorShapesCarryTheMessage() {
        let openAI = data(#"{"error":{"code":"invalid_parameter_error","param":null,"message":"\#(flashMessage)","type":"invalid_request_error"},"id":"chatcmpl-1"}"#)
        XCTAssertEqual(ThinkingProbe.message(from: openAI), flashMessage)
        let flat = data(#"{"request_id":"abc","code":"InvalidParameter","message":"\#(flashMessage)"}"#)
        XCTAssertEqual(ThinkingProbe.message(from: flat), flashMessage)
        XCTAssertEqual(ThinkingProbe.message(from: data("kein json")), "")
    }

    func testLevelProbeUsesAnImpossibleValueAndNoThinkingDirective() throws {
        let req = try ThinkingProbe.levelRequest(baseURL: "https://example.test/compatible-mode/v1",
                                                 key: "sk-test", model: "qwen3.8-flash")
        let body = try XCTUnwrap(self.body(of: req))
        XCTAssertEqual(body["reasoning_effort"] as? String, ThinkingProbe.invalidLevelValue)
        XCTAssertNil(body["enable_thinking"])
        XCTAssertNil(body["thinking_budget"])
        XCTAssertEqual(body["model"] as? String, "qwen3.8-flash")
        XCTAssertEqual(body["max_tokens"] as? Int, ThinkingProbe.maxTokens)
        XCTAssertEqual(req.url?.path, "/compatible-mode/v1/chat/completions")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
    }

    func testSwitchOffProbeAsksForThinkingOffOnly() throws {
        let req = try ThinkingProbe.switchOffRequest(baseURL: "https://example.test/compatible-mode/v1",
                                                     key: "sk-test", model: "glm-5.2")
        let body = try XCTUnwrap(self.body(of: req))
        XCTAssertEqual(body["enable_thinking"] as? Bool, false)
        XCTAssertNil(body["reasoning_effort"])
    }

    func testAnswerWithoutReasoningFieldMeansThinkingWasSwitchedOff() {
        let plain = data(#"{"choices":[{"message":{"role":"assistant","content":"OK"}}]}"#)
        XCTAssertNil(ThinkingProbe.reasoningText(from: plain))
        let reasoned = data(#"{"choices":[{"message":{"role":"assistant","reasoning_content":"rechnen","content":"OK"}}]}"#)
        XCTAssertEqual(ThinkingProbe.reasoningText(from: reasoned), "rechnen")
        let emptied = data(#"{"choices":[{"message":{"reasoning_content":"","content":"OK"}}]}"#)
        XCTAssertEqual(ThinkingProbe.reasoningText(from: emptied) ?? "", "")
        XCTAssertNil(ThinkingProbe.reasoningText(from: data("{}")))
    }

    func testProbedLevelsTogetherWithSwitchabilityDescribeTheModel() {
        let response = data(#"{"error":{"message":"\#(proMessage)"}}"#)
        let caps = ThinkingCapabilities(levels: ThinkingProbe.levels(in: ThinkingProbe.message(from: response)),
                                        canSwitchOff: true)
        XCTAssertTrue(caps.isKnown)
        XCTAssertEqual(caps.directive(for: .off), .suppressThinking)
        XCTAssertEqual(caps.directive(for: .minimal), .nothing)
    }
}
