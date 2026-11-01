@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import MapKit
import XCTest
import GwenMobileKit

@MainActor
private struct FixedLookup: ReminderPlaceLooking {
    var point: GeoPoint?

    func locate(_ name: String) async -> GeoPoint? { point }
}

private final class FixedNearbySearch: NearbyPlacing {
    let hits: [NearbyHit]
    let failure: Error?

    init(hits: [NearbyHit], failure: Error? = nil) {
        self.hits = hits
        self.failure = failure
    }

    func places(matching terms: [String], wish: String, mode: TravelMode) async throws -> [NearbyHit] {
        if let failure { throw failure }
        return hits
    }

    func route(to terms: [String], wish: String, mode: TravelMode) async throws -> [NearbyHit] {
        if let failure { throw failure }
        return hits
    }
}

@MainActor
final class ReminderPlaceLookupTests: GwenTestCase {
    func testTheNarrowRadiusIsTheSmallestAllowed() {
        XCTAssertEqual(ReminderPlaceRadius.fitting(region: nil), 150)
        XCTAssertEqual(ReminderPlaceRadius.fitting(region: 80), 150)
        XCTAssertEqual(ReminderPlaceRadius.fitting(region: .nan), 150)
    }

    func testALargerRegionKeepsItsRadiusUpToTheWidest() {
        XCTAssertEqual(ReminderPlaceRadius.fitting(region: 3_000), 3_000)
        XCTAssertEqual(ReminderPlaceRadius.fitting(region: 250_000), 10_000)
    }

    func testTheNearbyLookupTakesTheClosestHitWithinReach() async {
        let coordinate = CLLocationCoordinate2D(latitude: 48.1, longitude: 11.5)
        let item = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                             address: nil)
        let near = NearbyHit(item: item, place: NearbyPlace(name: "REWE", latitude: 48.1,
                                                            longitude: 11.5, metres: 400))
        let far = NearbyHit(item: item, place: NearbyPlace(name: "Fern", latitude: 48.2,
                                                           longitude: 11.6, metres: 90_000))
        let lookup = NearbyReminderPlaceLookup(search: FixedNearbySearch(hits: [far, near]))
        let point = await lookup.locate("REWE")
        XCTAssertEqual(point?.radius, ReminderPlaceRadius.narrow)
        XCTAssertEqual(point?.latitude ?? 0, 48.1, accuracy: 0.001)
        let empty = NearbyReminderPlaceLookup(search: FixedNearbySearch(hits: []))
        let nothing = await empty.locate("Nirgendwo")
        XCTAssertNil(nothing)
        let failing = NearbyReminderPlaceLookup(search: FixedNearbySearch(hits: [],
                                                                          failure: APIError(message: "kaputt")))
        let failed = await failing.locate("REWE")
        XCTAssertNil(failed)
    }

    func testTheChainPrefersTheNearbyLookupAndFallsBackToTheGeocoder() async {
        let nearby = GeoPoint(latitude: 48.1, longitude: 11.5, radius: 150)
        let city = GeoPoint(latitude: 48.6, longitude: 10.1, radius: 3_000)
        let chain = ReminderPlaceLookupChain(first: FixedLookup(point: nearby),
                                             second: FixedLookup(point: city))
        let preferred = await chain.locate("REWE")
        XCTAssertEqual(preferred, nearby)
        let fallback = ReminderPlaceLookupChain(first: FixedLookup(point: nil),
                                                second: FixedLookup(point: city))
        let cityHit = await fallback.locate("Berlin")
        XCTAssertEqual(cityHit, city)
        let nothing = ReminderPlaceLookupChain(first: FixedLookup(point: nil),
                                               second: FixedLookup(point: nil))
        let missed = await nothing.locate("Nirgendwo")
        XCTAssertNil(missed)
    }
}
