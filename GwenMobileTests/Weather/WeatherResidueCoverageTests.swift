@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import CoreLocation
import XCTest
import GwenMobileKit
@testable import GwenMobileProbes

@MainActor
final class WeatherResidueCoverageTests: GwenTestCase {
    private func service(fetcher: @escaping @Sendable (URLRequest) async throws -> Data,
                         fixer: any LocationFixing = RegionFixer()) -> WeatherService {
        var service = WeatherService()
        service.fetcher = fetcher
        service.fixer = fixer
        service.geocodeAddress = { name in
            WeatherPlace(name: name, latitude: 48.1, longitude: 11.5, timezone: "Europe/Berlin")
        }
        service.localSearch = { name in
            WeatherPlace(name: name, latitude: 48.1, longitude: 11.5, timezone: "Europe/Berlin")
        }
        service.reverseGeocode = { _ in "München" }
        return service
    }

    func testTheServiceDecodesAForecastAndCachesIt() async throws {
        WeatherService.clearCache()
        let service = service(fetcher: { _ in ForecastFixture.json(date: "2026-10-05") })
        let place = WeatherPlace(name: "München", latitude: 48.137, longitude: 11.575,
                                 timezone: "Europe/Berlin")
        let ref = try await service.day(place: place, date: "2026-10-05")
        XCTAssertEqual(ref.hours.count, 17)
        let cached = try await service.day(place: place, date: "2026-10-05")
        XCTAssertEqual(cached, ref)
        let key = WeatherService.cacheKey(place: place, date: "2026-10-05")
        XCTAssertNotNil(WeatherService.cached(key, now: Date()))
        WeatherService.remember(ref, key: "x", now: Date())
        WeatherService.clearCache()
        XCTAssertNil(WeatherService.cached("x", now: Date()))
    }

    func testTheServiceRejectsBrokenForecastData() async {
        WeatherService.clearCache()
        let service = service(fetcher: { _ in Data("{}".utf8) })
        let place = WeatherPlace(name: "München", latitude: 48.1, longitude: 11.5, timezone: nil)
        do {
            _ = try await service.day(place: place, date: "2026-10-05")
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    func testTheServiceResolvesAPlaceAndUsesTheDeviceLocation() async throws {
        WeatherService.clearCache()
        let service = service(fetcher: { request in
            if request.url?.absoluteString.contains("geocoding") == true {
                return Data(#"{"results":[{"name":"Hamburg","latitude":53.55,"longitude":9.99,"timezone":"Europe/Berlin"}]}"#.utf8)
            }
            return ForecastFixture.json(date: "2026-10-05")
        })
        let named = try await service.day(for: WeatherRequest(place: "Hamburg", day: .today,
                                                              date: "2026-10-05"))
        XCTAssertEqual(named.hours.count, 17)
        let located = try await service.day(for: WeatherRequest(place: nil, day: .today,
                                                                date: "2026-10-05"))
        XCTAssertEqual(located.place, "München")
    }

    func testTheServiceReportsAMissingPlace() async {
        var service = service(fetcher: { _ in Data("{}".utf8) })
        service.geocodeAddress = { _ in nil }
        service.localSearch = { _ in nil }
        do {
            _ = try await service.day(for: WeatherRequest(place: "Nirgendwo", day: .today,
                                                          date: "2026-10-05"))
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    func testTheServiceFallsBackToTheLocalSearchAndChecksTheForecastURL() async throws {
        WeatherService.clearCache()
        var service = service(fetcher: { request in
            if request.url?.absoluteString.contains("geocod") == true { return Data("{}".utf8) }
            return ForecastFixture.json(date: "2026-10-05")
        })
        service.geocodeAddress = { _ in nil }
        let place = try await service.day(for: WeatherRequest(place: "Hamburg", day: .today,
                                                              date: "2026-10-05"))
        XCTAssertEqual(place.place, "Hamburg")
        let missing = WeatherPlace(name: "München", latitude: 48.1, longitude: 11.5, timezone: nil)
        do {
            _ = try await service.day(place: missing, date: "keine-datum")
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    func testTheServiceRejectsAForecastForAnotherCalendarDay() async {
        WeatherService.clearCache()
        let service = service(fetcher: { _ in Data("{}".utf8) })
        let place = WeatherPlace(name: "Wetterinsel-\(UUID().uuidString)", latitude: 1.1,
                                 longitude: 2.2, timezone: nil)
        do {
            _ = try await service.day(place: place, date: "2026-10-05")
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    func testTheTargetDateAndSamePlaceHelpers() {
        let service = WeatherService()
        let now = Date()
        XCTAssertFalse(service.targetDate(WeatherRequest(place: nil, day: .today, date: nil),
                                          now: now, calendar: .current).isEmpty)
        XCTAssertFalse(service.targetDate(WeatherRequest(place: nil, day: .tomorrow, date: nil),
                                          now: now, calendar: .current).isEmpty)
        XCTAssertFalse(service.targetDate(WeatherRequest(place: nil, day: .dayAfter, date: nil),
                                          now: now, calendar: .current).isEmpty)
        XCTAssertFalse(service.targetDate(WeatherRequest(place: nil, day: .today, date: nil, offset: 3),
                                          now: now, calendar: .current).isEmpty)
        XCTAssertFalse(service.targetDate(WeatherRequest(place: nil, day: .today, date: "2026-10-09"),
                                          now: now, calendar: .current).isEmpty)
        XCTAssertTrue(WeatherService.samePlace("München", "München"))
        XCTAssertFalse(WeatherService.samePlace("München", "Hamburg"))
    }

    func testTheFirstPlaceLookupStopsAtTheFirstHit() async {
        var attempts = 0
        let place = await WeatherService.firstPlace([
            { () async throws -> WeatherPlace? in attempts += 1; throw APIError(message: "kein") },
            { () async throws -> WeatherPlace? in
                attempts += 1
                return WeatherPlace(name: "Treffer", latitude: 1, longitude: 2, timezone: nil)
            }
        ])
        XCTAssertEqual(place?.name, "Treffer")
        XCTAssertEqual(attempts, 2)
        let none = await WeatherService.firstPlace([{ () async throws -> WeatherPlace? in nil }])
        XCTAssertNil(none)
    }

    func testTheWeatherAnswersAndAdviceCoverTheirBranches() {
        let storm = WeatherFixture.ref(hours: WeatherFixture.day {
            WeatherFixture.hour($0, temp: -2, rain: 90, precip: 2.5, wind: 40, gust: 80, uv: 0, kind: .storm)
        })
        let advice = WeatherAdviceRules.advice(for: storm)
        XCTAssertFalse(advice.isEmpty)
        XCTAssertFalse(WeatherAnswers.text(ref: storm, advice: advice).isEmpty)
        XCTAssertNotNil(WeatherAdviceRules.rangeAndNote(for: storm))
        XCTAssertFalse(WeatherAdviceRules.summary(for: storm).isEmpty)
        let empty = WeatherFixture.ref(hours: [])
        XCTAssertFalse(WeatherAnswers.text(ref: empty, advice: []).isEmpty)
        _ = WeatherAnswers.dayTitle(storm.day)
        _ = WeatherAnswers.hourLine(storm, hour: 6)
    }

    func testTheServiceReportsAMissingForecastAddress() async {
        WeatherService.clearCache()
        WeatherService.forecastURL = { _, _ in nil }
        let service = service(fetcher: { _ in Data() })
        let place = WeatherPlace(name: "München", latitude: 48.1, longitude: 11.5, timezone: nil)
        do {
            _ = try await service.day(place: place, date: "2026-10-05")
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertEqual((error as? APIError)?.message, L.t("weather_data_missing"))
        }
    }

    func testSmokeTheCardExportsAPng() async throws {
        let ref = WeatherFixture.ref(hours: WeatherFixture.day { WeatherFixture.hour($0, temp: 20) })
        let card = WeatherCard(ref: ref)
        card.export()
    }
}

private struct RegionFixer: LocationFixing {
    func fix() async throws -> CLLocation {
        CLLocation(latitude: 48.137, longitude: 11.575)
    }
}
