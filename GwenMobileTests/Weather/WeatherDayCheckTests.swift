@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class WeatherDayCheckTests: GwenTestCase {
    private func weather(_ arguments: String) throws -> ToolDecision {
        try XCTUnwrap(ToolRouter.map(name: ToolRouter.weatherTool, arguments: arguments))
    }

    func testAFilledDayNeedsNoCheck() async throws {
        let decision = try weather(#"{"place":"München","dayOffset":4}"#)
        var asked = false
        let checked = await WeatherDayCheck().checked(decision, wish: "in 4 Tagen") { _ in
            asked = true
            return nil
        }
        XCTAssertFalse(asked)
        XCTAssertEqual(checked.route, decision.route)
    }

    func testAMissingDayIsAskedAgain() async throws {
        let decision = try weather(#"{"place":"München"}"#)
        let corrected = try weather(#"{"place":"München","dayOffset":3}"#)
        var hint = ""
        let checked = await WeatherDayCheck().checked(decision, wish: "überübermorgen") { received in
            hint = received
            return corrected
        }
        XCTAssertEqual(checked.route, corrected.route)
        if case .weather(let request) = checked.route {
            XCTAssertEqual(request.offset, 3)
        } else {
            XCTFail("keine Wetterroute")
        }
        XCTAssertTrue(hint.contains(PromptLibrary.text("router_relative_days")), hint)
        XCTAssertTrue(hint.contains("dayOffset"), hint)
    }

    private var fixedCheck: WeatherDayCheck {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 14)) ?? Date()
        return WeatherDayCheck(now: { now }, calendar: calendar)
    }

    func testADateThatContradictsTheOffsetIsAskedAgain() async throws {
        let decision = try weather(#"{"place":"Hamburg","date":"2026-10-29","dayOffset":3}"#)
        let corrected = try weather(#"{"place":"Hamburg","date":"2026-10-30","dayOffset":3}"#)
        var hint = ""
        let checked = await fixedCheck.checked(decision, wish: "überübermorgen") { received in
            hint = received
            return corrected
        }
        XCTAssertEqual(checked.route, corrected.route)
        XCTAssertTrue(hint.contains("date 2026-10-29 lies 2 days after today, but dayOffset is 3"), hint)
        XCTAssertTrue(hint.contains(PromptLibrary.text("router_relative_days")), hint)
        XCTAssertFalse(hint.contains("{{"), hint)
    }

    func testADateThatMatchesTheOffsetNeedsNoCheck() async throws {
        let decision = try weather(#"{"place":"Hamburg","date":"2026-10-30","dayOffset":3}"#)
        var asked = false
        let checked = await fixedCheck.checked(decision, wish: "überübermorgen") { _ in
            asked = true
            return nil
        }
        XCTAssertFalse(asked)
        XCTAssertEqual(checked.route, decision.route)
    }

    func testADateAloneOrAnUnreadableDateNeedsNoCheck() async throws {
        let check = fixedCheck
        for arguments in [#"{"place":"Hamburg","date":"2026-10-30"}"#,
                          #"{"place":"Hamburg","date":"nächsten Freitag","dayOffset":3}"#] {
            let decision = try weather(arguments)
            var asked = false
            let checked = await check.checked(decision, wish: "Freitag") { _ in
                asked = true
                return nil
            }
            XCTAssertFalse(asked, arguments)
            XCTAssertEqual(checked.route, decision.route, arguments)
        }
    }

    func testARenewedCallWithoutADayKeepsTheOriginal() async throws {
        let check = fixedCheck
        let dayless = try weather(#"{"place":"Hamburg"}"#)
        for arguments in [#"{"place":"Hamburg","date":"2026-10-29","dayOffset":3}"#, #"{"place":"München"}"#] {
            let decision = try weather(arguments)
            let checked = await check.checked(decision, wish: "überübermorgen") { _ in dayless }
            XCTAssertEqual(checked.route, decision.route, arguments)
        }
    }

    func testAnotherToolInTheRenewedCallKeepsTheOriginal() async throws {
        let decision = try weather(#"{"place":"Hamburg","date":"2026-10-29","dayOffset":3}"#)
        let other = try XCTUnwrap(ToolRouter.map(name: ToolRouter.answerTool, arguments: "{}"))
        let checked = await fixedCheck.checked(decision, wish: "überübermorgen") { _ in other }
        XCTAssertEqual(checked.route, decision.route)
    }

    func testAnUnreachableReaskKeepsTheOriginal() async throws {
        let decision = try weather(#"{"place":"München"}"#)
        let checked = await WeatherDayCheck().checked(decision, wish: "morgen") { _ in nil }
        XCTAssertEqual(checked.route, decision.route)
    }

    func testANonWeatherCallStaysUntouched() async throws {
        let decision = try XCTUnwrap(ToolRouter.map(name: ToolRouter.answerTool, arguments: "{}"))
        var asked = false
        let checked = await WeatherDayCheck().checked(decision, wish: "hallo") { _ in
            asked = true
            return nil
        }
        XCTAssertFalse(asked)
        XCTAssertEqual(checked.route, .chat)
    }
}
