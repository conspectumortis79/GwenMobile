@testable import GwenMobileFeatureCore
import MapKit
import UIKit
import XCTest
import GwenMobileKit

private struct GapPlaceFixer: LocationFixing {
    func fix() async throws -> CLLocation {
        CLLocation(latitude: 48.137, longitude: 11.575)
    }
}

@MainActor
final class PlacesLogicGapTests: GwenTestCase {
    private func item(_ name: String, latitude: Double = 48.137, longitude: Double = 11.575)
        -> MKMapItem {
        let item = MKMapItem(location: CLLocation(latitude: latitude, longitude: longitude), address: nil)
        item.name = name
        return item
    }

    func testThePlaceSearchStatics() {
        let origin = CLLocation(latitude: 48.137, longitude: 11.575)
        let request = PlaceSearch.request(for: "Apotheke", origin: origin)
        XCTAssertEqual(request.naturalLanguageQuery, "Apotheke")
        _ = PlaceSearch.request(for: "Apotheke", origin: nil)
        let mapItem = item("Apotheke")
        _ = PlaceSearch.address(of: mapItem)
        _ = PlaceSearch.coordinate(of: mapItem)
        let hit = NearbyHit(item: mapItem, place: NearbyPlace(name: "Apotheke", latitude: 48.137,
                                                              longitude: 11.575, metres: 120))
        XCTAssertTrue(hit.candidate.label.contains("Apotheke"))
        let hits = PlaceSearch.hits(from: [mapItem], around: origin, mode: .walking)
        XCTAssertEqual(hits.count, 1)
        _ = PlaceSearch.hits(from: [mapItem], around: nil, mode: .cycling)
        _ = PlaceSearch.ranked(hits, wish: "Apotheke", byDistance: true)
        _ = PlaceSearch.ranked(hits, wish: "Apotheke", byDistance: false)
    }

    func testTheRouteOpening() {
        var place = NearbyPlace(name: "Apotheke")
        XCTAssertFalse(place.openRoute())
        _ = AppleMapsOpener().open(place)
        place.latitude = 48.137
        place.longitude = 11.575
        place.mode = .cycling
        _ = place.directionsURL
    }

    func testSmokeTheLiveSearchWithAFakeFixer() async {
        let search = LivePlaceSearch(fixer: GapPlaceFixer())
        _ = try? await search.places(matching: ["Apotheke"], wish: "Apotheke", mode: .walking)
        _ = try? await search.route(to: ["Museum"], wish: "Museum", mode: .cycling)
        _ = try? await search.places(matching: [], wish: "", mode: .walking)
    }
}
