@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class ReadAloudRequestTests: GwenTestCase {
    func testTruthyAndFalsyArgumentsAreRead() {
        XCTAssertEqual(ReadAloudRequest.from(["enabled": true])?.enabled, true)
        XCTAssertEqual(ReadAloudRequest.from(["enabled": false])?.enabled, false)
        XCTAssertEqual(ReadAloudRequest.from(["enabled": "on"])?.enabled, true)
        XCTAssertEqual(ReadAloudRequest.from(["enabled": "off"])?.enabled, false)
        XCTAssertEqual(ReadAloudRequest.from(["enabled": 1])?.enabled, true)
        XCTAssertEqual(ReadAloudRequest.from(["enabled": 0])?.enabled, false)
    }

    func testWithoutAReadableSwitchThereIsNoRequest() {
        XCTAssertNil(ReadAloudRequest.from([:]))
        XCTAssertNil(ReadAloudRequest.from(["enabled": "maybe"]))
    }

    func testTheStepWordsNameTheDirection() {
        XCTAssertEqual(ReadAloudRequest(enabled: true).stepWords, "on")
        XCTAssertEqual(ReadAloudRequest(enabled: false).stepWords, "off")
    }
}

final class ReadAloudRoutingTests: GwenTestCase {
    private func readAloudFunction() throws -> [String: Any] {
        try toolFunction(ToolRouter.readAloudTool)
    }

    func testTheToolAsksOnlyForTheSwitch() throws {
        XCTAssertTrue(ToolSchemaNames.of(ToolRouter.tools(attachable: false)).contains(ToolRouter.readAloudTool))
        let parameters = try XCTUnwrap(try readAloudFunction()["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["required"] as? [String], ["enabled"])
        let properties = try XCTUnwrap(parameters["properties"] as? [String: Any])
        XCTAssertEqual(properties.keys.sorted(), ["enabled"])
    }

    func testTheDescriptionKeepsMusicListeningAndQuestionsAway() throws {
        let description = try XCTUnwrap(try readAloudFunction()["description"] as? String)
        XCTAssertTrue(description.contains("voice"), description)
        XCTAssertTrue(description.contains("music"), description)
        XCTAssertTrue(description.contains("listening mode"), description)
        XCTAssertTrue(description.contains(ToolRouter.answerTool), description)
    }

    func testBothDirectionsBecomeTheirOwnRoute() {
        let on = ToolRouter.decisions(from: call(ToolRouter.readAloudTool, #"{"enabled":true}"#)).first
        XCTAssertEqual(on?.route, .readAloud(ReadAloudRequest(enabled: true)))
        XCTAssertEqual(on?.stepKind, .readAloud)
        let off = ToolRouter.decisions(from: call(ToolRouter.readAloudTool, #"{"enabled":false}"#)).first
        XCTAssertEqual(off?.route, .readAloud(ReadAloudRequest(enabled: false)))
        let words = ToolRouter.decisions(from: call(ToolRouter.readAloudTool, #"{"enabled":"off"}"#)).first
        XCTAssertEqual(words?.route, .readAloud(ReadAloudRequest(enabled: false)))
    }

    func testAMalformedSwitchFallsBackToChat() {
        XCTAssertEqual(ToolRouter.decisions(from: call(ToolRouter.readAloudTool, "{}")).first?.route, .chat)
        XCTAssertEqual(ToolRouter.decisions(from: call(ToolRouter.readAloudTool, #"{"enabled":"maybe"}"#)).first?.route,
                       .chat)
        XCTAssertEqual(ToolRouter.decisions(from: call(ToolRouter.readAloudTool, "{enabled")).first?.route, .chat)
    }

    func testTheSystemBlockNamesTheTool() {
        let block = ToolRouter.systemBlock(now: "x", context: SendContext(), transcript: "")
        XCTAssertTrue(block.contains(ToolRouter.readAloudTool), block)
        XCTAssertTrue(block.contains("reading answers aloud"), block)
    }
}

final class ReadAnswerRoutingTests: GwenTestCase {
    private func readAnswerFunction() throws -> [String: Any] {
        try toolFunction(ToolRouter.readAnswerTool)
    }

    func testTheToolNeedsNoArguments() throws {
        XCTAssertTrue(ToolSchemaNames.of(ToolRouter.tools(attachable: false)).contains(ToolRouter.readAnswerTool))
        let parameters = try XCTUnwrap(try readAnswerFunction()["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["required"] as? [String], [])
        let properties = try XCTUnwrap(parameters["properties"] as? [String: Any])
        XCTAssertTrue(properties.isEmpty)
    }

    func testTheDescriptionKeepsSwitchingAloudAndMusicAway() throws {
        let description = try XCTUnwrap(try readAnswerFunction()["description"] as? String)
        XCTAssertTrue(description.contains("switched off"), description)
        XCTAssertTrue(description.contains(ToolRouter.readAloudTool), description)
        XCTAssertTrue(description.contains("music"), description)
    }

    func testAReadOutLoudWishBecomesItsOwnRoute() {
        let decision = ToolRouter.decisions(from: call(ToolRouter.readAnswerTool, "{}")).first
        XCTAssertEqual(decision?.route, .readAnswer)
        XCTAssertEqual(decision?.stepKind, .readAnswer)
    }

    func testTheSystemBlockNamesTheTool() {
        let block = ToolRouter.systemBlock(now: "x", context: SendContext(), transcript: "")
        XCTAssertTrue(block.contains(ToolRouter.readAnswerTool), block)
        XCTAssertTrue(block.contains("read out loud once"), block)
    }

    func testReadingTheAnswerKeepsItsOwnBubbleAfterTheAnswer() throws {
        let answer = try XCTUnwrap(ToolRouter.map(name: ToolRouter.answerTool, arguments: "{}"))
        let read = try XCTUnwrap(ToolRouter.map(name: ToolRouter.readAnswerTool, arguments: "{}"))
        let plan = SendPlan.forming([answer, read])
        XCTAssertEqual(plan.traceLine, "chat+readAnswer")
        XCTAssertFalse(plan.merges)
    }

    func testReadingThePreviousAnswerStaysBeforeAnUnrelatedTask() {
        let read = ToolDecision(route: .readAnswer)
        let timer = ToolDecision(route: .timer(TimerRequest(minutes: 5, seconds: nil, title: "Tee")))
        XCTAssertEqual(SendPlan.forming([read, timer]).traceLine, "readAnswer+timer")
    }
}
