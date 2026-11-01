@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
private final class FakeTimerSetter: TimerSetting {
    let result: TimerSettingResult

    init(result: TimerSettingResult) {
        self.result = result
    }

    func set(_ request: TimerRequest) async -> TimerSettingResult { result }
}

@MainActor
final class ClockGapCoverageTests: GwenTestCase {
    func testTheStepWordsNameEveryPart() {
        XCTAssertEqual(TimerRequest(minutes: 2, seconds: 5, title: "Tee").stepWords, "Tee m2 s5")
        XCTAssertEqual(TimerRequest(minutes: nil, seconds: nil, title: nil).stepWords, "")
        XCTAssertEqual(TimerRequest(minutes: 1, seconds: nil, title: nil).stepWords, "m1")
        XCTAssertEqual(TimerRequest(minutes: nil, seconds: 30, title: nil).stepWords, "s30")
    }

    func testTheTimerAnswerTitle() {
        XCTAssertEqual(TimerAnswer.title(TimerRequest(minutes: 1, seconds: nil, title: "  Tee  ")), "Tee")
        XCTAssertEqual(TimerAnswer.title(TimerRequest(minutes: 1, seconds: nil, title: "   ")),
                       L.t("timer_default_title"))
    }

    func testTheSingularSecondAndTheUnavailableResult() {
        XCTAssertEqual(TimerAnswer.duration(61), "1 minute 1 second")
        let request = TimerRequest(minutes: 1, seconds: nil, title: nil)
        XCTAssertEqual(TimerAnswer.result(.unavailable, request: request), L.t("timer_unavailable"))
        XCTAssertEqual(TimerSettingResult.unavailable.trace, "nicht_verfuegbar")
        XCTAssertEqual(TimerSettingResult.failed("kaputt").trace, "fehler=kaputt")
        XCTAssertEqual(TimerSettingResult.denied.trace, "berechtigung=fehlt")
    }

    func testTheDebugTimerSetterCanBeReplacedAndRestored() async {
        let original = FakeTimerSetter(result: .denied)
        let desk = TimerDesk(setter: original)
        desk.stand(in: FakeTimerSetter(result: .unavailable))
        let replaced = await desk.setter.set(TimerRequest(minutes: 1, seconds: nil, title: nil))
        XCTAssertEqual(replaced, .unavailable)
        desk.stand(in: FakeTimerSetter(result: .failed("x")))
        let second = await desk.setter.set(TimerRequest(minutes: 1, seconds: nil, title: nil))
        XCTAssertEqual(second, .failed("x"))
        desk.restore()
        let restored = await desk.setter.set(TimerRequest(minutes: 1, seconds: nil, title: nil))
        XCTAssertEqual(restored, .denied)
        desk.restore()
    }
}
