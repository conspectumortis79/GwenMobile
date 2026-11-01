@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class DayBriefingRoutingTests: GwenTestCase {
    func testTheBriefingToolIsOffered() {
        XCTAssertTrue(ToolSchemaNames.of(ToolRouter.tools(attachable: false)).contains(ToolRouter.briefingTool))
    }

    func testTheBriefingToolNamesItsSourcesAndItsBan() throws {
        let description = try toolDescription(ToolRouter.briefingTool)
        XCTAssertTrue(description.contains("appointments"), description)
        XCTAssertTrue(description.contains("reminders"), description)
        XCTAssertTrue(description.contains("weather"), description)
        XCTAssertTrue(description.contains("single appointment"), description)
        let day = try XCTUnwrap(try toolProperties(ToolRouter.briefingTool)["day"] as? [String: Any])
        XCTAssertEqual(day["enum"] as? [String], ["today", "tomorrow", "dayAfter"])
    }

    func testTheBriefingCallMapsOntoItsRoute() throws {
        for (raw, expected) in [("today", BriefingDay.today), ("tomorrow", .tomorrow),
                                ("dayAfter", .dayAfter)] {
            let decision = try XCTUnwrap(ToolRouter.decisions(from: call(ToolRouter.briefingTool,
                                                                        ["day": raw])).first)
            guard case .dayBriefing(let request) = decision.route else {
                return XCTFail("day_briefing landete nicht im Briefing: \(decision.route)")
            }
            XCTAssertEqual(request.day, expected)
            XCTAssertEqual(decision.stepKind, .briefing)
        }
    }

    func testAMissingOrUnknownDayStaysToday() throws {
        let missing = try XCTUnwrap(ToolRouter.decisions(from: call(ToolRouter.briefingTool, [:])).first)
        guard case .dayBriefing(let request) = missing.route else { return XCTFail("kein Briefing") }
        XCTAssertEqual(request.day, .today)
        let unknown = try XCTUnwrap(ToolRouter.decisions(from: call(ToolRouter.briefingTool,
                                                                   ["day": "nextweek"])).first)
        guard case .dayBriefing(let fallback) = unknown.route else { return XCTFail("kein Briefing") }
        XCTAssertEqual(fallback.day, .today)
    }

    func testTheBriefingStepDoesNotMergeIntoAnotherAnswer() throws {
        let brief = try XCTUnwrap(ToolRouter.map(name: ToolRouter.briefingTool,
                                                 arguments: #"{"day":"today"}"#))
        let answer = try XCTUnwrap(ToolRouter.map(name: ToolRouter.answerTool, arguments: "{}"))
        let plan = SendPlan.forming([brief, answer])
        XCTAssertEqual(plan.actions.count, 2)
        XCTAssertFalse(plan.merges)
    }

    func testTheSystemBlockNamesTheBriefingTool() {
        let block = ToolRouter.systemBlock(now: "x", context: SendContext(), transcript: "")
        XCTAssertTrue(block.contains(ToolRouter.briefingTool), block)
        XCTAssertTrue(block.contains("summary of the day"), block)
    }
}
