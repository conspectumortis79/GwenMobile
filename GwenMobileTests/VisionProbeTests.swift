import XCTest
@testable import GwenMobile

final class VisionProbeTests: XCTestCase {
    private let supportedBody = Data(#"{"choices":[{"message":{"content":"Rot"}}],"usage":{"prompt_tokens":90,"completion_tokens":3,"total_tokens":93,"prompt_tokens_details":{"image_tokens":66,"text_tokens":24,"cached_tokens":0}}}"#.utf8)
    private let blindBody = Data(#"{"choices":[{"message":{"content":"Schwarz"}}],"usage":{"prompt_tokens":18,"completion_tokens":3,"total_tokens":21,"prompt_tokens_details":{"cached_tokens":0}}}"#.utf8)
    private let zeroTokensBody = Data(#"{"choices":[],"usage":{"prompt_tokens":18,"prompt_tokens_details":{"image_tokens":0}}}"#.utf8)

    private let noDetailsBody = Data(#"{"choices":[],"usage":{"prompt_tokens":20,"completion_tokens":2}}"#.utf8)

    private func response(_ status: Int, _ body: Data) -> ProbeResponse {
        ProbeResponse(status: status, body: body)
    }

    private func body(of req: URLRequest) -> [String: Any]? {
        guard let data = req.httpBody else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    func testOnlyReportedImageTokensProveVision() {
        XCTAssertEqual(VisionProbe.support(response: response(200, supportedBody)), .supported)
        XCTAssertEqual(VisionProbe.imageTokens(in: supportedBody), 66)
    }

    func testAnswerWithoutImageTokensMeansTheModelIgnoredThePicture() {
        XCTAssertEqual(VisionProbe.support(response: response(200, blindBody)), .rejected)
        XCTAssertNil(VisionProbe.imageTokens(in: blindBody))
        XCTAssertEqual(VisionProbe.support(response: response(200, zeroTokensBody)), .rejected)
    }

    func testRefusedContentShapeIsRejectedAndNotUnknown() {
        let refused = Data(#"{"error":{"code":"invalid_parameter_error","message":"The provided messages input is invalid. The error info is [Unexpected item type in content.].","type":"invalid_request_error"}}"#.utf8)
        XCTAssertEqual(VisionProbe.support(response: response(400, refused)), .rejected)
    }

    func testProviderBreakdownAndMissingAnswerStayUnknown() {
        XCTAssertEqual(VisionProbe.support(response: response(500, Data("{}".utf8))), .unknown)
        XCTAssertEqual(VisionProbe.support(response: nil), .unknown)
        XCTAssertEqual(VisionProbe.support(response: response(200, Data("kein json".utf8))), .unknown)
        XCTAssertEqual(VisionProbe.support(response: response(200, noDetailsBody)), .unknown)
        XCTAssertNil(VisionProbe.promptTokenDetails(in: noDetailsBody))
    }

    func testProbeRequestSendsOnePictureAndNoThinkingKeys() throws {
        let req = try VisionProbe.request(baseURL: "https://example.test/compatible-mode/v1",
                                          key: "sk-test", model: "qwen3.8-flash")
        let body = try XCTUnwrap(self.body(of: req))
        XCTAssertEqual(body["model"] as? String, "qwen3.8-flash")
        XCTAssertEqual(body["max_tokens"] as? Int, VisionProbe.maxTokens)
        XCTAssertNil(body["reasoning_effort"])
        XCTAssertNil(body["enable_thinking"])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 2)
        let image = try XCTUnwrap(content.first?["image_url"] as? [String: Any])
        XCTAssertEqual(image["url"] as? String, VisionProbe.imageDataURL)
        XCTAssertFalse(VisionProbe.imageDataURL.isEmpty)
        XCTAssertEqual(req.url?.path, "/compatible-mode/v1/chat/completions")
    }

    func testCapabilitiesCombineThinkingAndVisionForTheSettingsStore() throws {
        var caps = ModelCapabilities()
        XCTAssertFalse(caps.isComplete)
        caps.thinking = ThinkingCapabilities(levels: [.off, .low], canSwitchOff: true)
        XCTAssertFalse(caps.isComplete)
        caps.vision = .supported
        XCTAssertTrue(caps.isComplete)
        let data = try JSONEncoder().encode(["qwen3.8-flash": caps])
        XCTAssertEqual(try JSONDecoder().decode([String: ModelCapabilities].self, from: data)["qwen3.8-flash"], caps)
    }

    func testVisionListWaitsForTheProbeAndThenKeepsOnlyRealSeers() {
        let models = ["qwen3.8-flash", "deepseek-v4-pro", "glm-5.2", "wan2.7-image", "qwen-audio-3.0-tts-plus"]
        XCTAssertEqual(ModelFilter.visionCandidates(models, caps: [:]),
                       ["qwen3.8-flash", "deepseek-v4-pro", "glm-5.2"])
        let caps: [String: ModelCapabilities] = [
            "qwen3.8-flash": ModelCapabilities(vision: .supported),
            "deepseek-v4-pro": ModelCapabilities(vision: .rejected),
            "glm-5.2": ModelCapabilities(vision: .rejected),
        ]
        XCTAssertEqual(ModelFilter.visionCandidates(models, caps: caps), ["qwen3.8-flash"])
        let noneBlind: [String: ModelCapabilities] = [
            "qwen3.8-flash": ModelCapabilities(vision: .rejected),
            "deepseek-v4-pro": ModelCapabilities(vision: .rejected),
        ]
        XCTAssertEqual(ModelFilter.visionCandidates(models, caps: noneBlind), [])
    }

    func testUnknownVisionStateNeverHidesTheModelList() {
        let models = ["qwen3.8-flash", "glm-5.2"]
        let caps: [String: ModelCapabilities] = ["qwen3.8-flash": ModelCapabilities(vision: .supported)]
        XCTAssertEqual(ModelFilter.visionCandidates(models, caps: caps), ["qwen3.8-flash"])
        let untouched: [String: ModelCapabilities] = ["glm-5.2": ModelCapabilities()]
        XCTAssertEqual(ModelFilter.visionCandidates(models, caps: untouched), models)
    }
}
