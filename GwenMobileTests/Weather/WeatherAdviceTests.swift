@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class WeatherAdviceTests: GwenTestCase {
    private func advice(_ hours: [WeatherHour]) -> [WeatherAdvice] {
        WeatherAdviceRules.advice(for: WeatherFixture.ref(hours: hours))
    }

    private func titles(_ hours: [WeatherHour]) -> [String] {
        advice(hours).map(\.title)
    }

    func testAStormIsTheFirstRedAdvice() {
        let hours = WeatherFixture.day { WeatherFixture.hour($0, kind: $0 == 15 ? .storm : .rain) }
        let items = advice(hours)
        XCTAssertEqual(items.first?.level, .red)
        XCTAssertEqual(items.first?.title, L.t("weather_advice_storm"))
    }

    func testStrongGustsBringAWindWarning() {
        let hours = WeatherFixture.day { WeatherFixture.hour($0, gust: $0 == 14 ? 72 : 25, uv: 0) }
        let items = advice(hours)
        XCTAssertEqual(items.first?.level, .orange)
        XCTAssertEqual(items.first?.title, L.t("weather_advice_wind"))
        XCTAssertTrue(items.first?.detail.contains("72") ?? false)
    }

    func testRainBringsTheUmbrellaAdvice() {
        let hours = WeatherFixture.day { WeatherFixture.hour($0, rain: $0 == 8 ? 80 : 10,
                                                             precip: $0 == 8 ? 2 : 0, uv: 0) }
        let items = advice(hours)
        XCTAssertEqual(items.first?.level, .blue)
        XCTAssertEqual(items.first?.title, L.t("weather_advice_umbrella"))
    }

    func testZeroProbabilityNeverAsksForAnUmbrella() {
        let byAmount = WeatherFixture.day {
            WeatherFixture.hour($0, rain: 0, precip: $0 == 8 ? 2 : 0, uv: 0)
        }
        let item = advice(byAmount).first
        XCTAssertEqual(item?.title, L.t("weather_advice_rain_possible"))
        XCTAssertNotEqual(item?.title, L.t("weather_advice_umbrella"))
        XCTAssertTrue(item?.detail.contains("2") ?? false, item?.detail ?? "")
    }

    func testLightRainBecomesAPossibilityWithoutUmbrella() {
        let hours = WeatherFixture.day {
            WeatherFixture.hour($0, rain: (6...7).contains($0) ? 35 : 5, precip: 0, uv: 0,
                                kind: (6...7).contains($0) ? .rain : .cloud)
        }
        let item = advice(hours).first
        XCTAssertEqual(item?.title, L.t("weather_advice_rain_possible"))
        XCTAssertTrue(item?.detail.contains("6") ?? false, item?.detail ?? "")
        XCTAssertTrue(item?.detail.contains("35") ?? false, item?.detail ?? "")
    }

    func testTheUmbrellaNamesTheRainWindow() {
        let hours = WeatherFixture.day {
            WeatherFixture.hour($0, rain: (8...11).contains($0) ? 80 : 10, precip: 0, uv: 0)
        }
        let item = advice(hours).first
        XCTAssertEqual(item?.title, L.t("weather_advice_umbrella"))
        XCTAssertTrue(item?.detail.contains("8") ?? false, item?.detail ?? "")
        XCTAssertTrue(item?.detail.contains("11") ?? false, item?.detail ?? "")
        XCTAssertTrue(item?.detail.contains("80") ?? false, item?.detail ?? "")
    }

    func testSunProtectionStartsAtUvThree() {
        let low = WeatherFixture.day { WeatherFixture.hour($0, temp: 24, rain: 0, uv: 2) }
        XCTAssertEqual(advice(low).first?.title, L.t("weather_advice_clear"))
        let moderate = WeatherFixture.day { WeatherFixture.hour($0, temp: 20, rain: 0, uv: 3) }
        let item = advice(moderate).first
        XCTAssertEqual(item?.title, L.t("weather_advice_uv"))
        XCTAssertTrue(item?.detail.contains("UV 3") ?? false, item?.detail ?? "")
    }

    func testTheUvDetailGrowsWithTheIndex() {
        let high = WeatherFixture.day { WeatherFixture.hour($0, rain: 0, uv: 7) }
        let extreme = WeatherFixture.day { WeatherFixture.hour($0, rain: 0, uv: 9) }
        XCTAssertEqual(advice(high).first?.title, L.t("weather_advice_uv"))
        XCTAssertNotEqual(advice(high).first?.detail, advice(extreme).first?.detail)
        XCTAssertTrue(advice(extreme).first?.detail.contains("9") ?? false,
                      advice(extreme).first?.detail ?? "")
    }

    func testHeatAndUvAdvice() {
        let hot = WeatherFixture.day { WeatherFixture.hour($0, temp: $0 == 15 ? 31 : 28, rain: 0, uv: 2) }
        XCTAssertEqual(titles(hot).first, L.t("weather_advice_heat"))
        let sunny = WeatherFixture.day { WeatherFixture.hour($0, temp: 22, rain: 0, uv: $0 == 13 ? 6 : 4) }
        XCTAssertEqual(titles(sunny).first, L.t("weather_advice_uv"))
    }

    func testACalmDayStaysGreen() {
        let hours = WeatherFixture.day { WeatherFixture.hour($0, temp: 18, rain: 5, wind: 8, gust: 20, uv: 1) }
        let items = advice(hours)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.level, .green)
        XCTAssertEqual(items.first?.title, L.t("weather_advice_clear"))
    }

    func testTheOrderPutsTheMostImportantAdviceFirst() {
        let hours = WeatherFixture.day { index in
            WeatherFixture.hour(index, temp: 31, rain: 80, precip: 1.5,
                                gust: 70, uv: 6, kind: index == 15 ? .storm : .rain)
        }
        XCTAssertEqual(titles(hours), [L.t("weather_advice_storm"), L.t("weather_advice_wind"),
                                       L.t("weather_advice_umbrella"), L.t("weather_advice_heat"),
                                       L.t("weather_advice_uv")])
    }

    func testTheSummaryNamesTheRainWindow() {
        let morning = WeatherFixture.day { WeatherFixture.hour($0, rain: $0 < 12 ? 70 : 10, kind: $0 < 12 ? .rain : .cloud) }
        XCTAssertEqual(WeatherAdviceRules.summary(for: WeatherFixture.ref(hours: morning)),
                       L.t("weather_sum_rain_morning"))
        let afternoon = WeatherFixture.day { WeatherFixture.hour($0, rain: $0 >= 15 ? 70 : 10, kind: $0 >= 15 ? .rain : .cloud) }
        XCTAssertEqual(WeatherAdviceRules.summary(for: WeatherFixture.ref(hours: afternoon)),
                       L.t("weather_sum_rain_afternoon"))
    }

    func testTheSummaryNamesSunHeatAndStorms() {
        let sun = WeatherFixture.day { WeatherFixture.hour($0, temp: 24, kind: .sun) }
        XCTAssertEqual(WeatherAdviceRules.summary(for: WeatherFixture.ref(hours: sun)), L.t("weather_sum_sun"))
        let heat = WeatherFixture.day { WeatherFixture.hour($0, temp: $0 == 15 ? 33 : 28, kind: .sun) }
        XCTAssertEqual(WeatherAdviceRules.summary(for: WeatherFixture.ref(hours: heat)), L.t("weather_sum_heat"))
        let storm = WeatherFixture.day { WeatherFixture.hour($0, kind: $0 == 15 ? .storm : .cloud) }
        XCTAssertEqual(WeatherAdviceRules.summary(for: WeatherFixture.ref(hours: storm)), L.t("weather_sum_storm"))
    }

    func testNumberFormatsValuesAndRefusesUnrepresentableOnes() {
        XCTAssertEqual(WeatherAdviceRules.number(21.6), "22")
        XCTAssertEqual(WeatherAdviceRules.number(-3.4), "-3")
        XCTAssertEqual(WeatherAdviceRules.number(1e300), "–")
        XCTAssertEqual(WeatherAdviceRules.number(-1e300), "–")
        XCTAssertEqual(WeatherAdviceRules.number(.nan), "–")
        XCTAssertEqual(WeatherAdviceRules.number(.infinity), "–")
    }
}
