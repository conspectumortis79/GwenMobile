@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class SendPlanDetailsTests: GwenTestCase {
    func testTheMissingStepNamesAreReachable() {
        let code = ToolDecision(route: .code(language: .swift))
        XCTAssertEqual(code.stepKind, .code)
        XCTAssertEqual(code.stepDetail, "swift")
        let german = ToolDecision(route: .translate(TranslationJob(text: "Hallo", targetCode: "en")))
        XCTAssertTrue(german.stepDetail.contains("Hallo"), german.stepDetail)
        XCTAssertTrue(german.stepDetail.contains("en"), german.stepDetail)
        let route = ToolDecision(route: .routeToPlace(terms: ["a", "b"], mode: .driving))
        XCTAssertEqual(route.stepKind, .route)
        XCTAssertTrue(route.stepDetail.contains("a b"), route.stepDetail)
        let picture = ToolDecision(route: .imageCreate)
        XCTAssertEqual(picture.stepDetail, "")
        let timer = ToolDecision(route: .timer(TimerRequest(minutes: 5, seconds: nil, title: "Tee")))
        XCTAssertFalse(timer.stepDetail.isEmpty)
        let readAloud = ToolDecision(route: .readAloud(ReadAloudRequest(enabled: false)))
        XCTAssertFalse(readAloud.stepDetail.isEmpty)
        let weather = ToolDecision(route: .weather(WeatherRequest(place: nil, day: .tomorrow, date: nil)))
        XCTAssertTrue(weather.stepDetail.hasPrefix("hier"), weather.stepDetail)
    }

    func testAnEmptyPlanStillHasAChatPrimary() {
        XCTAssertEqual(SendPlan(actions: []).primary.route, .chat)
    }

    func testTwoMemoryFactsAreNotTheSameStep() {
        let tea = ToolDecision(route: .memory(MemoryRequest(action: .create, text: "mag Tee")))
        let meat = ToolDecision(route: .memory(MemoryRequest(action: .create, text: "isst kein Fleisch")))
        XCTAssertNotEqual(tea.stepKey, meat.stepKey)
        XCTAssertEqual(SendPlan.forming([tea, meat]).actions.count, 2)
    }

    func testTwoWeatherDaysWithOffsetsAreNotTheSameStep() {
        let today = ToolDecision(route: .weather(WeatherRequest(place: "Berlin", day: .today,
                                                               date: nil, offset: 0)))
        let dayAfter = ToolDecision(route: .weather(WeatherRequest(place: "Berlin", day: .dayAfter,
                                                                  date: nil, offset: 2)))
        XCTAssertNotEqual(today.stepKey, dayAfter.stepKey)
        XCTAssertEqual(SendPlan.forming([today, dayAfter]).actions.count, 2)
    }

    func testPriceWatchesWithoutWordsAreNotTheSameProduct() {
        let empty = ToolDecision(route: .priceWatch(PriceWatchRequest(action: .create, terms: [], goal: 400)))
        let words = ToolDecision(route: .priceWatch(PriceWatchRequest(action: .create, terms: ["PlayStation 5"], goal: 400)))
        XCTAssertEqual(SendPlan.forming([empty, words]).actions.count, 2)
        let long = ToolDecision(route: .priceWatch(PriceWatchRequest(action: .create, terms: ["PlayStation 5"], goal: 400)))
        let shorter = ToolDecision(route: .priceWatch(PriceWatchRequest(action: .create, terms: ["PlayStation"], goal: 400)))
        XCTAssertEqual(SendPlan.forming([long, shorter]).actions.count, 1)
    }
}
