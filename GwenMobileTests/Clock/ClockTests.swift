@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class ClockTests: GwenTestCase {
    private let evening = Date(timeIntervalSince1970: 1_790_795_640)
    private let berlin = TimeZone(identifier: "Europe/Berlin")!

    private func clockFunction() throws -> [String: Any] {
        try toolFunction(ToolRouter.clockTool)
    }

    private func decision(_ arguments: String) -> ToolDecision? {
        ToolRouter.map(name: ToolRouter.clockTool, arguments: arguments)
    }

    func testTheFixedMomentIsTheEveningOfTheLastSeptemberDay() {
        XCTAssertEqual(ClockAnswer.render(evening, zone: berlin, date: .none, time: .short), "9:14\u{202F}PM")
    }

    func testTheClockToolIsOfferedAndNeedsNoArgument() throws {
        XCTAssertTrue(ToolSchemaNames.of(ToolRouter.tools(attachable: false)).contains(ToolRouter.clockTool))
        XCTAssertTrue(ToolSchemaNames.of(ToolRouter.tools(attachable: true)).contains(ToolRouter.clockTool))
        let parameters = try XCTUnwrap(try clockFunction()["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["required"] as? [String], [])
        XCTAssertEqual((parameters["properties"] as? [String: Any])?.keys.sorted(), ["place", "timeZone"])
    }

    func testTheDescriptionKeepsCalculationsAndRemindersAway() throws {
        let description = try XCTUnwrap(try clockFunction()["description"] as? String)
        XCTAssertTrue(description.contains("answer_in_chat or search_web"), description)
        XCTAssertTrue(description.contains(ToolRouter.calendarTool), description)
    }

    func testTheRouterPolicyNamesTheClockTool() {
        let system = ToolRouter.systemBlock(now: "heute", context: SendContext(), transcript: "")
        XCTAssertTrue(system.contains("Use \(ToolRouter.clockTool) whenever"), system)
    }

    func testTheModelOnlyNamesThePlaceAndTheDeviceKeepsTheClock() {
        XCTAssertEqual(decision("{}")?.route, .clock(ClockRequest()))
        XCTAssertEqual(decision(#"{"timeZone":"Asia/Tokyo","place":"Tokio"}"#)?.route,
                       .clock(ClockRequest(timeZone: "Asia/Tokyo", place: "Tokio")))
        XCTAssertEqual(decision(#"{"timeZone":"","place":""}"#)?.route, .clock(ClockRequest()))
        XCTAssertEqual(decision(#"{}"#)?.stepKind, .clock)
    }

    func testAnUnknownZoneOrAPlaceWithoutZoneGoesToTheChatInsteadOfTheWrongClock() {
        XCTAssertEqual(decision(#"{"timeZone":"Mond/Krater"}"#)?.route, .chat)
        XCTAssertEqual(decision(#"{"place":"Hintertupfingen"}"#)?.route, .chat,
                       "ohne Zone wäre die eigene Uhrzeit für einen fremden Ort falsch")
    }

    func testTheOwnClockAnswersInGerman() {
        L.apply(.de)
        XCTAssertEqual(ClockAnswer.text(now: evening, request: ClockRequest(), home: berlin),
                       "🕒 Es ist 21:14 Uhr — Mittwoch, 30. September 2026.")
        L.apply(.en)
    }

    func testAnotherZoneAlsoMovesTheDate() {
        XCTAssertEqual(ClockAnswer.text(now: evening, request: ClockRequest(timeZone: "Asia/Tokyo", place: "Tokio"),
                                        home: berlin),
                       "🕒 In Tokio it is 4:14\u{202F}AM — Thursday, October 1, 2026.")
    }

    func testWithoutAPlaceTheCityComesFromTheZone() {
        let request = ClockRequest(timeZone: "America/New_York")
        XCTAssertEqual(request.placeName, "New York")
        XCTAssertEqual(ClockAnswer.text(now: evening, request: request, home: berlin),
                       "🕒 In New York it is 3:14\u{202F}PM — Wednesday, September 30, 2026.")
    }

    func testTheEnglishAnswerUsesTheEnglishClock() {
        L.apply(.en)
        let text = ClockAnswer.text(now: evening, request: ClockRequest(), home: berlin)
        XCTAssertTrue(text.hasPrefix("🕒 It is 9:14"), text)
        XCTAssertTrue(text.contains("PM"), text)
        XCTAssertTrue(text.hasSuffix("Wednesday, September 30, 2026."), text)
    }

    func testTwoClocksInOneMessageStayTwoLinesOfOneAnswer() {
        let plan = SendPlan.forming([ToolDecision(route: .clock(ClockRequest(timeZone: "Asia/Tokyo"))),
                                     ToolDecision(route: .clock(ClockRequest(timeZone: "America/New_York")))])
        XCTAssertEqual(plan.actions.map(\.stepKind), [.clock, .clock])
        XCTAssertTrue(plan.merges)
    }

    func testTheSplitterKnowsTheTimeIsAWishOfItsOwn() {
        XCTAssertTrue(WishSplitter.system().contains("tell the time of one place"), WishSplitter.system())
    }

    func testTheChatModelKnowsTheLocalTimeAndZone() {
        let prompt = SystemPrompt.chat()
        XCTAssertTrue(prompt.contains("Local time: "), prompt)
        XCTAssertTrue(prompt.contains(TimeZone.current.identifier), prompt)
        XCTAssertNotNil(SystemPrompt.currentTime().range(of: "^\\d{2}:\\d{2}$", options: .regularExpression))
    }
}
