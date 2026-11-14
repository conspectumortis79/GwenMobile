@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class QwenAndProbeCoverageTests: GwenTestCase {
    override func tearDown() {
        MockHTTP.uninstall()
        super.tearDown()
    }

    func testTheChatRequestBuildsSystemAndParts() throws {
        let request = try QwenAPI.makeRequest(
            baseURL: "https://q.test/v1", key: "k", model: "m",
            messages: [ChatMessage(role: .user, text: "Hallo", images: [Attachment(file: "a.jpg")])],
            imageData: [Data([1, 2, 3])], stream: true, thinking: .nothing)
        let httpBody = try XCTUnwrap(request.httpBody)
        let object = try JSONSerialization.jsonObject(with: httpBody)
        let body = try XCTUnwrap(object as? [String: Any])
        let messages = body["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.count, 2)
        XCTAssertEqual(messages?.first?["role"] as? String, "system")
        XCTAssertEqual(body["stream"] as? Bool, true)
        XCTAssertTrue(try XCTUnwrap(QwenAPI.dataURL(Data([1, 2, 3]))).hasPrefix("data:image/"))
    }

    func testTheCalendarPlanParsesAToolCall() async throws {
        MockHTTP.install { _ in
            let json = #"{"choices":[{"message":{"content":"{\"action\":\"create\",\"title\":\"Zahnarzt\",\"start\":\"2026-10-05 09:00\"}"}}]}"#
            return (200, Data(json.utf8))
        }
        let plan = try await QwenAPI.calendarPlan(baseURL: "https://q.test/v1", key: "k", model: "m",
                                                  instruction: "Termin morgen", history: [], events: "",
                                                  calendars: "", planned: "", thinking: .nothing)
        XCTAssertEqual(plan?.action, .create)
        XCTAssertEqual(plan?.title, "Zahnarzt")
    }

    func testTheCapabilityProberDiscoversAModel() async {
        MockHTTP.install { _ in
            (200, Data(#"{"choices":[{"message":{"content":"OK"}}],"usage":{"prompt_tokens_details":{"image_tokens":10}}}"#.utf8))
        }
        let prober = CapabilityProber(requiresImageTokens: false) { _, _, _ in
            ThinkingCapabilities(levels: [.low], encoding: .openAI)
        }
        let caps = await prober.discover(baseURL: "https://q.test/v1", key: "k", models: ["m1", "m2", "m3"])
        XCTAssertEqual(caps.keys.sorted(), ["m1", "m2", "m3"])
        for value in caps.values {
            XCTAssertTrue(value.isComplete)
        }
    }
}
