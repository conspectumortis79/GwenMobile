@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class TimerRequestTests: GwenTestCase {
    func testMinutesAndSecondsBecomeOneDuration() {
        XCTAssertEqual(TimerRequest(minutes: 5, seconds: nil, title: nil).duration, 300)
        XCTAssertEqual(TimerRequest(minutes: 1, seconds: 30, title: nil).duration, 90)
        XCTAssertEqual(TimerRequest(minutes: nil, seconds: 10, title: nil).duration, 10)
    }

    func testTheRouterArgumentsAreReadEvenWhenTheyArriveAsText() throws {
        let fromNumbers = try XCTUnwrap(TimerRequest.from(["minutes": 5, "seconds": 30]))
        XCTAssertEqual(fromNumbers.duration, 330)
        let fromStrings = try XCTUnwrap(TimerRequest.from(["minutes": "2", "seconds": "15"]))
        XCTAssertEqual(fromStrings.duration, 135)
        let fromDecimal = try XCTUnwrap(TimerRequest.from(["seconds": 10.0]))
        XCTAssertEqual(fromDecimal.duration, 10)
    }

    func testWithoutADurationThereIsNoTimerRequest() {
        XCTAssertNil(TimerRequest.from([:]))
        XCTAssertNil(TimerRequest.from(["minutes": 0, "seconds": 0]))
        XCTAssertNil(TimerRequest.from(["title": "Tee"]))
    }

    func testAbsurdlyLargeNumbersCannotCrashTheRequest() {
        XCTAssertNil(TimerRequest.from(["minutes": 1e30]))
        XCTAssertNil(TimerRequest.from(["seconds": Double.infinity]))
        XCTAssertEqual(TimerRequest.from(["minutes": 10.5])?.minutes, 10)
        let huge = TimerRequest.from(["minutes": 1_000_000_000_000_000_000])
        XCTAssertNotNil(huge)
        XCTAssertGreaterThan(huge?.duration ?? 0, 0)
    }
}

final class TimerAnswerTests: GwenTestCase {
    func testTheDurationReadsInMinutesAndSeconds() {
        XCTAssertEqual(TimerAnswer.duration(10), "10 seconds")
        XCTAssertEqual(TimerAnswer.duration(60), "1 minute")
        XCTAssertEqual(TimerAnswer.duration(90), "1 minute 30 seconds")
        XCTAssertEqual(TimerAnswer.duration(600), "10 minutes")
    }

    func testTheResultNamesTitleAndDuration() {
        let request = TimerRequest(minutes: nil, seconds: 10, title: "Tee")
        XCTAssertEqual(TimerAnswer.result(.set(duration: 10, way: "alarmkit"), request: request),
                       "⏱ Timer set: Tee for 10 seconds")
    }

    func testATimerWithoutANameReadsJustTheDuration() {
        let request = TimerRequest(minutes: nil, seconds: 10, title: nil)
        XCTAssertEqual(TimerAnswer.result(.set(duration: 10, way: "alarmkit"), request: request),
                       "⏱ Timer set: 10 seconds")
    }

    func testADeniedAlarmGetsItsOwnNotice() {
        let request = TimerRequest(minutes: 1, seconds: nil, title: nil)
        XCTAssertEqual(TimerAnswer.result(.denied, request: request), L.t("timer_denied"))
        XCTAssertEqual(TimerAnswer.result(.failed("x"), request: request), L.t("timer_failed"))
    }

    func testTheDurationAndTraceSurviveAHugeTimer() {
        XCTAssertFalse(TimerAnswer.duration(1e30).isEmpty)
        XCTAssertTrue(TimerSettingResult.set(duration: 1e30, way: "alarmkit")
            .trace.contains("gestellt="))
    }
}

final class TimerRoutingTests: GwenTestCase {
    private func timerFunction() throws -> [String: Any] {
        try toolFunction(ToolRouter.timerTool)
    }

    func testTheTimerToolAsksOnlyForADuration() throws {
        XCTAssertTrue(ToolSchemaNames.of(ToolRouter.tools(attachable: false)).contains(ToolRouter.timerTool))
        let parameters = try XCTUnwrap(try timerFunction()["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["required"] as? [String], [])
        let properties = try XCTUnwrap(parameters["properties"] as? [String: Any])
        XCTAssertEqual(properties.keys.sorted(), ["minutes", "seconds", "title"])
    }

    func testTheTimerDescriptionKeepsRemindersAppointmentsAndTimeAway() throws {
        let description = try XCTUnwrap(try timerFunction()["description"] as? String)
        XCTAssertTrue(description.contains("explicitly asks"), description)
        XCTAssertTrue(description.contains(ToolRouter.reminderTool), description)
        XCTAssertTrue(description.contains(ToolRouter.calendarTool), description)
        XCTAssertTrue(description.contains(ToolRouter.clockTool), description)
    }

    func testAFullTimerWishBecomesItsOwnRoute() {
        let minutes = ToolRouter.decisions(from: call(ToolRouter.timerTool, #"{"minutes":5}"#)).first
        XCTAssertEqual(minutes?.route, .timer(TimerRequest(minutes: 5, seconds: nil, title: nil)))
        XCTAssertEqual(minutes?.stepKind, .timer)
        let seconds = ToolRouter.decisions(from: call(ToolRouter.timerTool, #"{"seconds":10,"title":"Tee"}"#)).first
        XCTAssertEqual(seconds?.route, .timer(TimerRequest(minutes: nil, seconds: 10, title: "Tee")))
        let both = ToolRouter.decisions(from: call(ToolRouter.timerTool, #"{"minutes":1,"seconds":30}"#)).first
        guard case .timer(let request)? = both?.route else { return XCTFail("kein Timer: \(both?.route as Any)") }
        XCTAssertEqual(request.duration, 90)
    }

    func testWithoutADurationTheTimerToolFallsBackToChat() {
        XCTAssertEqual(ToolRouter.decisions(from: call(ToolRouter.timerTool, "{}")).first?.route, .chat)
        XCTAssertEqual(ToolRouter.decisions(from: call(ToolRouter.timerTool, #"{"minutes":0}"#)).first?.route, .chat)
        XCTAssertEqual(ToolRouter.decisions(from: call(ToolRouter.timerTool, "{seconds")).first?.route, .chat)
    }

    func testAReminderKeepsItsOwnToolForTimedWishes() {
        let block = ToolRouter.systemBlock(now: "x", context: SendContext(), transcript: "")
        XCTAssertTrue(block.contains(ToolRouter.timerTool), block)
        XCTAssertTrue(block.contains("explicitly asks"), block)
        let reminder = ToolRouter.tools(attachable: false).first {
            ($0["function"] as? [String: Any])?["name"] as? String == ToolRouter.reminderTool
        }
        let description = try? XCTUnwrap((reminder?["function"] as? [String: Any])?["description"] as? String)
        XCTAssertTrue(description?.contains(ToolRouter.timerTool) ?? false, description ?? "")
    }

    func testTheSplitterKnowsATimerIsAWishOfItsOwn() {
        let system = WishSplitter.system()
        XCTAssertTrue(system.contains("set one timer"), system)
        XCTAssertTrue(system.contains("A timer the user asks to set is one wish"), system)
    }
}
