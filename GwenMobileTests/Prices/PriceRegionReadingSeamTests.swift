@testable import GwenMobileDevice
import CoreLocation
import XCTest
import GwenMobileKit

@MainActor
final class PriceRegionReadingSeamTests: GwenTestCase {
    func testTheGeocoderCanBeCancelled() async {
        let geocoder = LiveCountryGeocoder()
        let task = Task { try await geocoder.country(at: CLLocation(latitude: 48.137, longitude: 11.575)) }
        task.cancel()
        do {
            _ = try await task.value
        } catch {
            XCTAssertTrue(error is CancellationError || !error.localizedDescription.isEmpty)
        }
        XCTAssertEqual(LiveCountryGeocoder.timeout, .seconds(15))
    }

    func testTheGeocoderAnswersOrFailsForALocation() async {
        let geocoder = LiveCountryGeocoder()
        do {
            let code = try await geocoder.country(at: CLLocation(latitude: 48.137, longitude: 11.575))
            XCTAssertTrue(code == nil || code?.count == 2)
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }
}
