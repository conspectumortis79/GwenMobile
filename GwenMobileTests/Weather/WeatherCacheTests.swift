@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit
@testable import GwenMobileProbes

@MainActor
final class WeatherCacheTests: GwenTestCase {
    private var place: WeatherPlace { WeatherPlace(name: "München", latitude: 48.137, longitude: 11.575,
                                                   timezone: "Europe/Berlin") }
    private let date = "2026-10-05"

    private func service(calls: LockedValue<Int>) -> WeatherService {
        WeatherService.clearCache()
        var service = WeatherService()
        let fallback = date
        service.fetcher = { request in
            calls.mutate { $0 += 1 }
            let asked = request.url
                .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
                .queryItems?.first { $0.name == "start_date" }?.value
            return ForecastFixture.json(date: asked ?? fallback)
        }
        return service
    }

    func testSecondRequestComesFromTheCache() async throws {
        let calls = LockedValue(0)
        let service = service(calls: calls)
        let first = try await service.day(place: place, date: date)
        let second = try await service.day(place: place, date: date)
        XCTAssertEqual(calls.current, 1)
        XCTAssertEqual(first, second)
    }

    func testAnotherDayIsFetchedAgain() async throws {
        let calls = LockedValue(0)
        let service = service(calls: calls)
        _ = try await service.day(place: place, date: date)
        _ = try await service.day(place: place, date: "2026-10-06")
        XCTAssertEqual(calls.current, 2)
    }

    func testAnEntryExpiresAfterTheLifetime() async throws {
        let calls = LockedValue(0)
        let service = service(calls: calls)
        let now = Date()
        _ = try await service.day(place: place, date: date, now: now)
        _ = try await service.day(place: place, date: date,
                                  now: now.addingTimeInterval(WeatherService.cacheLifetime + 1))
        XCTAssertEqual(calls.current, 2)
    }

    func testClearingTheCacheForcesAFetch() async throws {
        let calls = LockedValue(0)
        let service = service(calls: calls)
        _ = try await service.day(place: place, date: date)
        WeatherService.clearCache()
        _ = try await service.day(place: place, date: date)
        XCTAssertEqual(calls.current, 2)
    }

    func testTheCacheIsBoundedToItsLimit() {
        let now = Date()
        WeatherService.clearCache()
        let hours = WeatherFixture.day { WeatherFixture.hour($0) }
        for index in 0...WeatherService.cacheLimit {
            let key = WeatherService.cacheKey(place: place, date: "2026-10-\(index)")
            WeatherService.remember(WeatherFixture.ref(hours: hours), key: key,
                                    now: now.addingTimeInterval(Double(index)))
        }
        XCTAssertNil(WeatherService.cached(WeatherService.cacheKey(place: place, date: "2026-10-0"), now: now),
                     "der älteste Eintrag fällt heraus")
        let newest = WeatherService.cacheKey(place: place, date: "2026-10-\(WeatherService.cacheLimit)")
        XCTAssertNotNil(WeatherService.cached(newest,
                                              now: now.addingTimeInterval(Double(WeatherService.cacheLimit))))
    }

    func testAFailedFetchIsNotCached() async {
        WeatherService.clearCache()
        var service = WeatherService()
        service.fetcher = { _ in throw APIError(message: "offline") }
        do {
            _ = try await service.day(place: place, date: date)
            XCTFail("der Fehler muss durchkommen")
        } catch {
            XCTAssertNil(WeatherService.cached(WeatherService.cacheKey(place: place, date: date), now: Date()))
        }
    }
}
