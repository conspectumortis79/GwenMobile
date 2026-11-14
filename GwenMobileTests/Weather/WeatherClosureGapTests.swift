@testable import GwenMobileFeatureCore
import GwenMobileKit
import XCTest

@MainActor
final class WeatherClosureGapTests: GwenTestCase {
    private func ref(_ kind: WeatherKind, temp: Double = 18, rain: Int = 0, precip: Double = 0,
                     gust: Double = 10, uv: Double = 1) -> WeatherRef {
        WeatherFixture.ref(hours: WeatherFixture.day {
            WeatherFixture.hour($0, temp: temp, rain: rain, precip: precip, wind: 5, gust: gust,
                                uv: uv, kind: kind)
        })
    }

    func testTheAdviceCoversEveryWeatherClosure() {
        let storm = ref(.storm, temp: 20, rain: 90, precip: 2, gust: 100, uv: 9)
        XCTAssertFalse(WeatherAdviceRules.advice(for: storm).isEmpty)
        let gusty = ref(.cloud, temp: 20, rain: 0, precip: 0, gust: 95, uv: 1)
        XCTAssertTrue(WeatherAdviceRules.advice(for: gusty).contains { $0.symbol == "exclamationmark.triangle.fill" })
        let wet = ref(.rain, temp: 16, rain: 60, precip: 1, gust: 20, uv: 2)
        XCTAssertFalse(WeatherAdviceRules.advice(for: wet).isEmpty)
        let hot = ref(.sun, temp: 34, rain: 0, precip: 0, gust: 10, uv: 9)
        XCTAssertFalse(WeatherAdviceRules.advice(for: hot).isEmpty)
        XCTAssertFalse(WeatherAdviceRules.summary(for: hot).isEmpty)
        XCTAssertNotNil(WeatherAdviceRules.rangeAndNote(for: hot))
        let clear = ref(.cloud, temp: 20, rain: 0, precip: 0, gust: 10, uv: 1)
        XCTAssertFalse(WeatherAdviceRules.advice(for: clear).isEmpty)
        XCTAssertFalse(WeatherAdviceRules.summary(for: clear).isEmpty)
    }

    func testTheAnswerTextCoversUmbrellaAndWind() {
        let wet = ref(.rain, temp: 16, rain: 60, precip: 1, gust: 70, uv: 1)
        let advice = WeatherAdviceRules.advice(for: wet)
        let text = WeatherAnswers.text(ref: wet, advice: advice)
        XCTAssertFalse(text.isEmpty)
        let leading = WeatherAdvice(level: .green, symbol: "checkmark.circle.fill", title: "Klar", detail: "trocken")
        let withUmbrella = [leading] + advice
        let mixed = WeatherAnswers.text(ref: wet, advice: withUmbrella)
        XCTAssertTrue(mixed.contains(L.t("weather_today")) || mixed.contains(wet.place))
    }

    func testTheDayTitleAndRequestHelpers() {
        XCTAssertFalse(WeatherAnswers.dayTitle("2026-10-05").isEmpty)
        XCTAssertEqual(WeatherAnswers.dayTitle("Unfug"), "Unfug")
        let request = WeatherRequest(place: "München", day: .dayAfter, date: nil, offset: nil)
        XCTAssertEqual(request.day.index, 2)
        let service = WeatherService()
        let date = service.targetDate(request, now: Date(), calendar: .current)
        XCTAssertFalse(date.isEmpty)
        let stamp = Formatters.stamp(Date())
        XCTAssertFalse(WeatherDayTabs.dates(selected: stamp, today: Date()).isEmpty)
        XCTAssertEqual(WeatherDayTabs.offset(of: stamp, today: Date()), 0)
    }
}
