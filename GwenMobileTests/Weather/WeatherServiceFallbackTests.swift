@testable import GwenMobileFeatureCore
import CoreLocation
import XCTest
import GwenMobileKit

@MainActor
private struct FailingLocationFix: LocationFixing {
    func fix() async throws -> CLLocation { throw CLError(.locationUnknown) }
}

final class WeatherServiceFallbackTests: GwenTestCase {
    private let hamburg = WeatherPlace(name: "Hamburg", latitude: 53.55, longitude: 10.0,
                                       timezone: "Europe/Berlin")

    @MainActor
    func testAFailingSourceHandsOverToTheNextSource() async {
        let place = hamburg
        var secondCalled = false
        let found = await WeatherService.firstPlace([
            { throw APIError(message: "offline") },
            { secondCalled = true; return place },
        ])
        XCTAssertTrue(secondCalled)
        XCTAssertEqual(found, place)
    }

    @MainActor
    func testAWorkingSourceStopsTheChain() async {
        let place = hamburg
        var secondCalled = false
        let found = await WeatherService.firstPlace([
            { place },
            { secondCalled = true; return nil },
        ])
        XCTAssertEqual(found, place)
        XCTAssertFalse(secondCalled)
    }

    @MainActor
    func testAnEmptyResultHandsOverWithoutFailing() async {
        let place = hamburg
        let found = await WeatherService.firstPlace([
            { nil },
            { place },
        ])
        XCTAssertEqual(found, place)
    }

    @MainActor
    func testAMissingLocationIsReportedAsItsOwnError() async {
        var service = WeatherService()
        service.fixer = FailingLocationFix()
        do {
            _ = try await service.day(for: WeatherRequest(place: nil, day: .today, date: nil), now: Date())
            XCTFail("ohne Ort darf kein Wetter entstehen")
        } catch {
            XCTAssertEqual((error as? APIError)?.message, L.t("weather_location_needed"))
        }
    }
}
