@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class NearbyPlaceTests: GwenTestCase {
    func testTheCoordinateKeyFormatsThePair() {
        let place = NearbyPlace(name: "REWE", latitude: 52.5, longitude: 13.4, metres: 800, mode: .walking)
        XCTAssertEqual(place.coordinateKey, "52.5000,13.4000")
        let without = NearbyPlace(name: "ohne", latitude: nil, longitude: nil, metres: nil, mode: .walking)
        XCTAssertNil(without.coordinateKey)
    }

    func testTheDistanceTextSwitchesToKilometres() {
        let metres = NearbyPlace(name: "nah", latitude: 1, longitude: 1, metres: 120, mode: .walking)
        XCTAssertEqual(metres.distanceText, L.n("place_metres", 120))
        let kilometres = NearbyPlace(name: "weit", latitude: 1, longitude: 1, metres: 1200, mode: .walking)
        XCTAssertEqual(kilometres.distanceText, L.n("place_kilometres", 1))
        let unknown = NearbyPlace(name: "?", latitude: nil, longitude: nil, metres: nil, mode: .walking)
        XCTAssertNil(unknown.distanceText)
    }

    func testTheDirectionsURLCarriesTheCoordinatesAndTheMode() throws {
        let place = NearbyPlace(name: "REWE", latitude: 52.5, longitude: 13.4, metres: nil, mode: .driving)
        let url = try XCTUnwrap(place.directionsURL)
        XCTAssertTrue(url.absoluteString.contains("daddr=52.500000,13.400000"), url.absoluteString)
        XCTAssertTrue(url.absoluteString.contains("dirflg=d"), url.absoluteString)
        let without = NearbyPlace(name: "x", latitude: nil, longitude: nil, metres: nil, mode: .driving)
        XCTAssertNil(without.directionsURL)
    }

    func testTheDecoderFillsTheDefaults() throws {
        let data = Data(#"{"name":"REWE","latitude":52.5}"#.utf8)
        let place = try JSONDecoder().decode(NearbyPlace.self, from: data)
        XCTAssertEqual(place.name, "REWE")
        XCTAssertEqual(place.mode, .walking)
        XCTAssertNil(place.metres)
        XCTAssertNil(place.longitude)
    }
}
