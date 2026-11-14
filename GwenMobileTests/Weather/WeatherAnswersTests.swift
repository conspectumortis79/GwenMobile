@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class WeatherAnswersTests: GwenTestCase {
    private func rainyRef() -> WeatherRef {
        let hours = WeatherFixture.day {
            WeatherFixture.hour($0, temp: $0 == 14 ? 13 : 10, rain: $0 == 8 ? 80 : 10,
                                precip: $0 == 8 ? 1.5 : 0, gust: 30, uv: 0,
                                kind: $0 < 12 ? .rain : .cloud)
        }
        return WeatherFixture.ref(place: "München", hours: hours)
    }

    func testTheTextLeadsWithTheAdvice() {
        let ref = rainyRef()
        let advice = WeatherAdviceRules.advice(for: ref)
        XCTAssertEqual(advice.first?.title, L.t("weather_advice_umbrella"))
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 4)) ?? Date()
        let text = WeatherAnswers.text(ref: ref, advice: advice, today: today)
        XCTAssertTrue(text.hasPrefix(L.fmt2("weather_intro_head", L.t("weather_tomorrow"), "München")), text)
        XCTAssertTrue(text.contains(L.fmt2("weather_temp_range", "10", "13")), text)
        XCTAssertTrue(text.contains(L.t("weather_sum_rain_morning")), text)
        XCTAssertTrue(text.contains(L.t("weather_advice_umbrella") + " —"), text)
        XCTAssertTrue(text.contains("80"), text)
    }

    func testTheHourLineCarriesAllValues() {
        let ref = WeatherFixture.ref(hours: [WeatherFixture.hour(14, temp: 13.4, rain: 25, gust: 40.2, uv: 3.1)])
        let line = WeatherAnswers.hourLine(ref, hour: 14)
        XCTAssertTrue(line.contains("14"))
        XCTAssertTrue(line.contains("13"))
        XCTAssertTrue(line.contains("25"))
        XCTAssertTrue(line.contains("40"))
        XCTAssertTrue(line.contains("3"))
        XCTAssertEqual(WeatherAnswers.hourLine(ref, hour: 4), "")
    }

    func testTheRangeKeyKeepsBothValues() {
        let text = L.fmt2("weather_temp_range", "9", "13")
        XCTAssertTrue(text.contains("9"))
        XCTAssertTrue(text.contains("13"))
        XCTAssertTrue(text.contains("°C"))
    }

    func testTheDayTitleNamesRelativeAndFixedDays() {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 4)) ?? Date()
        XCTAssertEqual(WeatherAnswers.dayTitle("2026-10-04", today: today), L.t("weather_today"))
        XCTAssertEqual(WeatherAnswers.dayTitle("2026-10-05", today: today), L.t("weather_tomorrow"))
        let later = WeatherAnswers.dayTitle("2026-10-08", today: today)
        XCTAssertNotEqual(later, L.t("weather_tomorrow"))
        XCTAssertTrue(later.contains("8"), later)
    }

    func testTheDayTitleFallsBackWhenTheDayCannotBeMeasured() {
        let original = WeatherAnswers.dayOffset
        defer { WeatherAnswers.dayOffset = original }
        WeatherAnswers.dayOffset = { _, _, _ in nil }
        XCTAssertEqual(WeatherAnswers.dayTitle("2026-10-08"), "2026-10-08")
    }
}
