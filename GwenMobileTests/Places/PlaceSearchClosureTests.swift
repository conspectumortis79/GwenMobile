@testable import GwenMobileFeatureCore
import GwenMobileKit
import CoreLocation
import MapKit
import XCTest

@MainActor
final class PlaceSearchClosureTests: GwenTestCase {
    private func item(name: String = "Laden", lat: Double = 48.1, lon: Double = 11.5) -> MKMapItem {
        let item = MKMapItem(location: CLLocation(latitude: lat, longitude: lon), address: nil)
        item.name = name
        return item
    }

    private struct FixedFixer: LocationFixing {
        func fix() async throws -> CLLocation { CLLocation(latitude: 48, longitude: 11) }
    }

    func testTheMapItemHelpers() {
        URLOpenSpy.install()
        defer { URLOpenSpy.uninstall() }
        let mapItem = NearbyPlace.mapItem(name: "Test", latitude: 48, longitude: 11)
        XCTAssertEqual(mapItem.name, "Test")
        _ = NearbyPlace.mapItemOpener(mapItem, [:])
        let plain = item()
        _ = PlaceSearch.address(of: plain)
        _ = PlaceSearch.coordinate(of: plain)
        let hits = PlaceSearch.hits(from: [plain], around: CLLocation(latitude: 48.2, longitude: 11.6),
                                    mode: .walking)
        XCTAssertFalse(hits.isEmpty)
    }

    func testTheLiveSearchUsesTheRunner() async throws {
        let item = item()
        LivePlaceSearch.searchRunner = { _ in [item] }
        defer {
            LivePlaceSearch.searchRunner = { request in
                try await LivePlaceSearch.searchRunnerDefault(request)
            }
        }
        let search = LivePlaceSearch(fixer: FixedFixer())
        let hits = try await search.places(matching: ["Laden"], wish: "Laden", mode: .walking)
        XCTAssertFalse(hits.isEmpty)
    }

    func testTheNearbySearchAlsoAsksWithTheUsersOwnWords() async throws {
        let asked = LockedValue<[String]>([])
        LivePlaceSearch.searchRunner = { request in
            asked.mutate { $0.append(request.naturalLanguageQuery ?? "") }
            return [self.item()]
        }
        defer {
            LivePlaceSearch.searchRunner = { request in
                try await LivePlaceSearch.searchRunnerDefault(request)
            }
        }
        let search = LivePlaceSearch(fixer: FixedFixer())
        _ = try await search.places(matching: ["Apotheke"], wish: "Apotheke am Markt", mode: .walking)
        XCTAssertTrue(asked.current.contains("Apotheke am Markt"))
    }
}
