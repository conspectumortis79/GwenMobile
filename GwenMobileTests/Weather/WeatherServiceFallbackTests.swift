@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

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
}
