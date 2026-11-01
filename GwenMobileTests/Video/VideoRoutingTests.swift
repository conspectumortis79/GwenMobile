@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class VideoRoutingTests: GwenTestCase {
    func testTheRouterMapsCreateVideoAndKeepsItsParameters() throws {
        let decision = try XCTUnwrap(ToolRouter.map(
            name: ToolRouter.videoTool,
            arguments: #"{"prompt":"Eine Katze im Regen","duration":8,"ratio":"9:16"}"#))
        guard case .videoCreate(let request) = decision.route else {
            return XCTFail("route was \(decision.route)")
        }
        XCTAssertEqual(request.prompt, "Eine Katze im Regen")
        XCTAssertEqual(request.duration, 8)
        XCTAssertEqual(request.ratio, .portrait)
        XCTAssertEqual(decision.stepKind, .video)
        XCTAssertFalse(decision.mergesIntoOneAnswer)
    }

    func testTheVideoCheckParsesAPositiveAndANegativeAnswer() {
        let positive = VideoWishCheck.parse(
            #"{"video":true,"prompt":"Ein Paar am Eiffelturm","duration":10,"ratio":"9:16"}"#,
            fallback: "Fallback")
        XCTAssertEqual(positive?.prompt, "Ein Paar am Eiffelturm")
        XCTAssertEqual(positive?.clampedDuration, 10)
        XCTAssertEqual(positive?.ratio, .portrait)
        let fallback = VideoWishCheck.parse(#"{"video":true}"#, fallback: "Fallback")
        XCTAssertEqual(fallback?.prompt, "Fallback")
        XCTAssertEqual(fallback?.ratio, .landscape)
        XCTAssertNil(VideoWishCheck.parse(#"{"video":false}"#, fallback: "Fallback"))
        XCTAssertNil(VideoWishCheck.parse("keine Antwort", fallback: "Fallback"))
    }

    func testCreateVideoWithoutAPromptFallsBackToChat() throws {
        let decision = try XCTUnwrap(ToolRouter.map(name: ToolRouter.videoTool,
                                                    arguments: #"{"duration":5}"#))
        XCTAssertEqual(decision.route, .chat)
    }

    func testTheToolSetCarriesCreateVideoWithARequiredPrompt() throws {
        let tools = ToolRouter.tools(attachable: true)
        let video = try XCTUnwrap(tools.first {
            ($0["function"] as? [String: Any])?["name"] as? String == ToolRouter.videoTool
        })
        let function = try XCTUnwrap(video["function"] as? [String: Any])
        let parameters = try XCTUnwrap(function["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["required"] as? [String], ["prompt"])
    }

    func testAnAttachedVideoAddsTheVideoRuleAndTheToolName() {
        var context = SendContext()
        context.attachedVideo = true
        let system = ToolRouter.systemBlock(now: "2026-11-01 12:00", context: context, transcript: "")
        XCTAssertTrue(system.contains(ToolRouter.videoTool))
        XCTAssertTrue(system.contains("A video is in play"))
        XCTAssertTrue(context.textNeedsTheModel)
    }

    func testAVideoGenerationNeverRunsBesideAnotherStep() {
        XCTAssertFalse(ChainSchedule.runsConcurrently(.video, translatesFromChat: false))
        XCTAssertFalse(ChainSchedule.runsConcurrently(.video, translatesFromChat: true))
    }

    func testAVideoStepStaysASeparateAnswer() {
        let video = ToolDecision(route: .videoCreate(VideoRequest(prompt: "Wellen")))
        let chat = ToolDecision(route: .chat)
        let plan = SendPlan.forming([video, chat])
        XCTAssertEqual(plan.actions.map(\.stepKind), [.video, .chat])
        XCTAssertFalse(plan.merges)
    }
}
