@testable import GwenMobileFeatureCore
import GwenMobileKit
import CoreLocation
import MapKit
import XCTest

@MainActor
final class PlaceSearchClosureTests: GwenTestCase {
    private struct AskedRequest: Sendable {
        let query: String
        let latitude: Double
        let longitude: Double
        let pinned: Bool
        let required: Bool
    }

    private func item(name: String = "Laden", lat: Double = 48.1, lon: Double = 11.5) -> MKMapItem {
        let item = MKMapItem(location: CLLocation(latitude: lat, longitude: lon), address: nil)
        item.name = name
        return item
    }

    private struct FixedFixer: LocationFixing {
        func fix() async throws -> CLLocation { CLLocation(latitude: 48, longitude: 11) }
    }

    private struct MissingFixer: LocationFixing {
        func fix() async throws -> CLLocation { throw CLError(CLError.locationUnknown) }
    }

    private struct DeniedFixer: LocationFixing {
        func fix() async throws -> CLLocation { throw APIError(message: L.t("place_denied")) }
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

    func testTheLiveSearchReturnsTheRequestedNumberOfPlaces() async throws {
        let items = (0..<6).map { index in
            item(name: "Fensterbauer \(index)", lat: 48.1 + Double(index) * 0.0001, lon: 11.5)
        }
        LivePlaceSearch.searchRunner = { _ in items }
        defer {
            LivePlaceSearch.searchRunner = { request in
                try await LivePlaceSearch.searchRunnerDefault(request)
            }
        }
        let search = LivePlaceSearch(fixer: FixedFixer())
        let hits = try await search.places(matching: ["Fensterbauer"], wish: "Fensterbauer",
                                           mode: .walking, count: 5)
        XCTAssertEqual(hits.count, 5)
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

    func testAFailedLocationStillSearchesThePlaceTheUserNamed() async throws {
        let wish = "Ich brauche einen Fensterbauer in Giengen an der Brenz"
        let anchor = item(name: "Giengen an der Brenz", lat: 48.619366, lon: 10.2337551)
        let business = item(name: "Finestra Fensterbau", lat: 48.6311657, lon: 10.1856577)
        let distant = item(name: "Fenster Braun", lat: 52.52, lon: 13.405)
        let requests = LockedValue<[AskedRequest]>([])
        LivePlaceSearch.searchRunner = { request in
            var required = false
            if #available(iOS 18.0, macOS 15.0, *) {
                required = request.regionPriority == .required
            }
            requests.mutate {
                $0.append(AskedRequest(query: request.naturalLanguageQuery ?? "",
                                       latitude: request.region.center.latitude,
                                       longitude: request.region.center.longitude,
                                       pinned: request.region.span.latitudeDelta > 0,
                                       required: required))
            }
            return request.region.span.latitudeDelta == 0 ? [anchor] : [business, anchor, distant]
        }
        defer {
            LivePlaceSearch.searchRunner = { request in
                try await LivePlaceSearch.searchRunnerDefault(request)
            }
        }
        let search = LivePlaceSearch(fixer: MissingFixer())
        let hits = try await search.places(matching: ["Fensterbau"], wish: wish, mode: .walking)
        XCTAssertEqual(hits.map(\.place.name), ["Finestra Fensterbau"])
        XCTAssertNil(hits.first?.place.metres)
        let anchorRequest = try XCTUnwrap(requests.current.first)
        XCTAssertEqual(anchorRequest.query, wish)
        XCTAssertFalse(anchorRequest.pinned)
        let pinned = requests.current.filter(\.pinned)
        XCTAssertFalse(pinned.isEmpty)
        for request in pinned {
            XCTAssertEqual(request.latitude, anchor.location.coordinate.latitude, accuracy: 0.0001)
            XCTAssertEqual(request.longitude, anchor.location.coordinate.longitude, accuracy: 0.0001)
            if #available(iOS 18.0, macOS 15.0, *) {
                XCTAssertTrue(request.required)
            }
        }
    }

    func testAFailedLocationWithoutANamedPlaceKeepsTheLocationMessage() async {
        LivePlaceSearch.searchRunner = { _ in [] }
        defer {
            LivePlaceSearch.searchRunner = { request in
                try await LivePlaceSearch.searchRunnerDefault(request)
            }
        }
        let search = LivePlaceSearch(fixer: MissingFixer())
        do {
            _ = try await search.places(matching: ["Fensterbauer"], wish: "Fensterbauer in meiner Nähe",
                                        mode: .walking)
            XCTFail("expected a location failure")
        } catch let error as APIError {
            XCTAssertEqual(error.message, L.t("place_unavailable"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testAFailedLocationWithoutANamedPlaceOrWordsKeepsTheLocationMessage() async {
        let calls = LockedValue<Int>(0)
        LivePlaceSearch.searchRunner = { _ in
            calls.mutate { $0 += 1 }
            return []
        }
        defer {
            LivePlaceSearch.searchRunner = { request in
                try await LivePlaceSearch.searchRunnerDefault(request)
            }
        }
        let search = LivePlaceSearch(fixer: MissingFixer())
        do {
            _ = try await search.places(matching: ["Fensterbauer"], wish: "", mode: .walking)
            XCTFail("expected a location failure")
        } catch let error as APIError {
            XCTAssertEqual(error.message, L.t("place_unavailable"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
        XCTAssertEqual(calls.current, 0)
    }

    func testAFailedAreaLookupKeepsTheLocationMessage() async {
        LivePlaceSearch.searchRunner = { _ in throw URLError(.notConnectedToInternet) }
        defer {
            LivePlaceSearch.searchRunner = { request in
                try await LivePlaceSearch.searchRunnerDefault(request)
            }
        }
        let search = LivePlaceSearch(fixer: MissingFixer())
        do {
            _ = try await search.places(matching: ["Fensterbauer"], wish: "Fensterbauer in meiner Nähe",
                                        mode: .walking)
            XCTFail("expected a location failure")
        } catch let error as APIError {
            XCTAssertEqual(error.message, L.t("place_unavailable"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testAFailedLocationKeepsADeniedMessage() async {
        LivePlaceSearch.searchRunner = { _ in [] }
        defer {
            LivePlaceSearch.searchRunner = { request in
                try await LivePlaceSearch.searchRunnerDefault(request)
            }
        }
        let search = LivePlaceSearch(fixer: DeniedFixer())
        do {
            _ = try await search.places(matching: ["Fensterbauer"], wish: "Fensterbauer in meiner Nähe",
                                        mode: .walking)
            XCTFail("expected a location failure")
        } catch let error as APIError {
            XCTAssertEqual(error.message, L.t("place_denied"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testASearchFailureBecomesThePlaceMessage() async {
        LivePlaceSearch.searchRunner = { _ in throw URLError(.notConnectedToInternet) }
        defer {
            LivePlaceSearch.searchRunner = { request in
                try await LivePlaceSearch.searchRunnerDefault(request)
            }
        }
        let search = LivePlaceSearch(fixer: FixedFixer())
        do {
            _ = try await search.places(matching: ["Apotheke"], wish: "Apotheke", mode: .walking)
            XCTFail("expected a search failure")
        } catch let error as APIError {
            XCTAssertEqual(error.message, L.t("place_none_found"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testAnAPISearchFailureIsKept() async {
        LivePlaceSearch.searchRunner = { _ in throw APIError(message: "boom") }
        defer {
            LivePlaceSearch.searchRunner = { request in
                try await LivePlaceSearch.searchRunnerDefault(request)
            }
        }
        let search = LivePlaceSearch(fixer: FixedFixer())
        do {
            _ = try await search.places(matching: ["Apotheke"], wish: "Apotheke", mode: .walking)
            XCTFail("expected a search failure")
        } catch let error as APIError {
            XCTAssertEqual(error.message, "boom")
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testANamedPlaceIsFoundFromTheUsersOwnWords() {
        let anchor = item(name: "Giengen an der Brenz", lat: 48.619366, lon: 10.2337551)
        let business = item(name: "Fenster Henle", lat: 48.629, lon: 10.164)
        XCTAssertEqual(PlaceSearch.area(in: [anchor], wish: "Fensterbauer in Giengen an der Brenz")?.name,
                       "Giengen an der Brenz")
        XCTAssertNil(PlaceSearch.area(in: [business], wish: "Fensterbauer in Giengen an der Brenz"))
    }
}
