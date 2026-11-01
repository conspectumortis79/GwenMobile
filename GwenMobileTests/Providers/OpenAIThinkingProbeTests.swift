@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class OpenAIThinkingProbeTests: XCTestCase {
    private func response(_ status: Int, _ message: String) -> ProbeResponse {
        let body = #"{"error":{"message":"\#(message)","type":"invalid_request_error","param":"reasoning_effort"}}"#
        return ProbeResponse(status: status, body: Data(body.utf8))
    }

    func testSupportedValuesListBecomesTheLevelSet() {
        let caps = OpenAIThinkingProbe.interpret(response(400,
            "Invalid value: '__gwen_sonde__'. Supported values are: 'none', 'low', 'medium', and 'high'."))
        XCTAssertEqual(caps.levels, [.off, .low, .medium, .high])
        XCTAssertTrue(caps.canSwitchOff)
        XCTAssertTrue(caps.probed)
        XCTAssertEqual(caps.encoding, .openAI)
        XCTAssertEqual(caps.directive(for: .off), .effort(.off, .openAI))
        XCTAssertEqual(caps.directive(for: .xhigh), .nothing)
    }

    func testTheQwenStyleMessageIsUnderstoodToo() {
        let caps = OpenAIThinkingProbe.interpret(response(400,
            "The parameter reasoning_effort must be one of: minimal, low, medium, high, xhigh, max."))
        XCTAssertEqual(caps.levels, [.minimal, .low, .medium, .high, .xhigh, .max])
        XCTAssertFalse(caps.canSwitchOff)
    }

    func testAModelWithoutTheParameterIsKnownAndOffersNothing() {
        let caps = OpenAIThinkingProbe.interpret(response(400,
            "Unsupported parameter: 'reasoning_effort' is not supported with this model."))
        XCTAssertTrue(caps.probed)
        XCTAssertTrue(caps.levels.isEmpty)
        XCTAssertFalse(caps.offersControl)
        XCTAssertEqual(caps.directive(for: .medium), .nothing)
        let unrecognized = OpenAIThinkingProbe.interpret(response(400,
            "Unrecognized request argument supplied: reasoning_effort"))
        XCTAssertTrue(unrecognized.probed)
    }

    func testUnrelatedErrorsAndAuthProblemsStayUnknown() {
        let unrelated = OpenAIThinkingProbe.interpret(response(400, "max_tokens is too low for this request"))
        XCTAssertFalse(unrelated.isKnown)
        XCTAssertTrue(unrelated.levels.isEmpty)
        XCTAssertFalse(OpenAIThinkingProbe.interpret(response(401, "invalid api key")).isKnown)
        XCTAssertFalse(OpenAIThinkingProbe.interpret(response(429, "rate limited")).isKnown)
        XCTAssertFalse(OpenAIThinkingProbe.interpret(response(500, "oops")).isKnown)
        XCTAssertFalse(OpenAIThinkingProbe.interpret(ProbeResponse(status: 200, body: Data("{}".utf8))).isKnown)
    }

    func testTokenScanNeverPicksLevelsFromForeignMessages() {
        XCTAssertEqual(ThinkingProbe.levelTokens(in: "temperature must be low or medium"), [])
        XCTAssertEqual(ThinkingProbe.levelTokens(in: "reasoning_effort: invalid value '__gwen_sonde__', expected one of high, low"),
                       [.high, .low])
        XCTAssertFalse(ThinkingProbe.deniesParameter("max_tokens is not supported"))
        XCTAssertTrue(ThinkingProbe.deniesParameter("This model does not support reasoning."))
    }

    func testAnUnknownUnprobedModelStillFallsBackToTheCoreLevelsInOpenAIStyle() {
        let unknown = ThinkingCapabilities(encoding: .openAI)
        XCTAssertEqual(unknown.directive(for: .medium), .effort(.medium, .openAI))
        XCTAssertEqual(unknown.directive(for: .medium).bodyEntries["reasoning_effort"] as? String, "medium")
        XCTAssertEqual(unknown.directive(for: .off), .nothing)
    }
}
