@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class HistoryRoutingTests: GwenTestCase {
    func testTheHistoryToolIsOffered() {
        XCTAssertTrue(ToolSchemaNames.of(ToolRouter.tools(attachable: false)).contains(ToolRouter.historyTool))
    }

    func testDeleteHistoryMapsOntoTheHistoryRoute() throws {
        let decision = try XCTUnwrap(ToolRouter.decisions(from: call(ToolRouter.historyTool, [:])).first)
        XCTAssertEqual(decision.route, .history)
        XCTAssertEqual(decision.stepKind, .history)
        let ignored = try XCTUnwrap(ToolRouter.decisions(
            from: call(ToolRouter.historyTool, ["scope": "current"])).first)
        XCTAssertEqual(ignored.route, .history)
    }

    func testTheHistoryToolCarriesNoScopeAndDeletesEverything() throws {
        let tool = ToolRouter.tools(attachable: false).first {
            ($0["function"] as? [String: Any])?["name"] as? String == ToolRouter.historyTool
        }
        let function = try XCTUnwrap(tool?["function"] as? [String: Any])
        let parameters = try XCTUnwrap(function["parameters"] as? [String: Any])
        let properties = try XCTUnwrap(parameters["properties"] as? [String: Any])
        XCTAssertTrue(properties.isEmpty)
        let description = try XCTUnwrap(function["description"] as? String)
        XCTAssertTrue(description.contains("every saved"))
        XCTAssertTrue(description.contains("empty"))
        XCTAssertTrue(description.contains("never a request to delete only the running conversation"))
    }

    func testAHistoryStepDoesNotMergeSilentlyIntoAnotherAnswer() throws {
        let erase = try XCTUnwrap(ToolRouter.map(name: ToolRouter.historyTool, arguments: "{}"))
        let answer = try XCTUnwrap(ToolRouter.map(name: ToolRouter.answerTool, arguments: "{}"))
        let plan = SendPlan.forming([erase, answer])
        XCTAssertEqual(plan.actions.count, 2)
        XCTAssertFalse(plan.merges)
    }

    func testTheSystemBlockCarriesTheConfiguredPhrase() {
        let block = ToolRouter.systemBlock(now: "2026-10-04 16:20", context: SendContext(), transcript: "",
                                           eraseHistoryWord: "Tafel abwischen")
        XCTAssertTrue(block.contains("Tafel abwischen"))
        XCTAssertTrue(block.contains(ToolRouter.historyTool))
    }

    func testTheSystemBlockNamesTheHistoryToolWithoutAPhrase() {
        let block = ToolRouter.systemBlock(now: "x", context: SendContext(), transcript: "")
        XCTAssertTrue(block.contains(ToolRouter.historyTool))
        XCTAssertFalse(block.contains("configured"))
    }

    func testTheHistoryWordIsNotALocalSpokenCommand() {
        let signals = VoiceSignals(wake: "hey gwen", stop: "senden", cancel: "abbrechen",
                                   newChat: "neuer chat", listenOff: "zuhören aus")
        XCTAssertNil(VoiceCommand.command(in: "Verlauf löschen", signals: signals))
        XCTAssertNil(VoiceCommand.command(in: "Tafel abwischen", signals: signals))
    }

    func testCompactRoutingKeepsOnlyTheNewestFourMessages() {
        let history = (0..<8).map { ChatMessage(role: .user, text: "m\($0)") }
        XCTAssertEqual(RouterHistory.forRouting(history, compact: true).map(\.text),
                       ["m4", "m5", "m6", "m7"])
        XCTAssertEqual(RouterHistory.forRouting(history, compact: false).map(\.text),
                       history.map(\.text))
        XCTAssertEqual(RouterHistory.forRouting(Array(history.prefix(2)), compact: true).map(\.text),
                       ["m0", "m1"])
    }
}
