@testable import GwenMobileFeatureCore
import MapKit
import XCTest
import GwenMobileKit

@MainActor
private final class RecordingPlaceSearch: NearbyPlacing {
    private(set) var calls: [String] = []
    let hits: [NearbyHit]
    let failure: Error?

    init(hits: [NearbyHit], failure: Error? = nil) {
        self.hits = hits
        self.failure = failure
    }

    func places(matching terms: [String], wish: String, mode: TravelMode) async throws -> [NearbyHit] {
        calls.append("places:\(terms.joined(separator: ","))|\(wish)")
        if let failure { throw failure }
        return hits
    }

    func route(to terms: [String], wish: String, mode: TravelMode) async throws -> [NearbyHit] {
        calls.append("route:\(terms.joined(separator: ","))|\(wish)")
        if let failure { throw failure }
        return hits
    }
}

@MainActor
final class PlaceFlowRunnerTests: GwenTestCase {
    private func hit(_ name: String, _ metres: Int?) -> NearbyHit {
        let place = NearbyPlace(name: name, latitude: 52.52, longitude: 13.405, metres: metres)
        return NearbyHit(item: MKMapItem(), place: place)
    }

    func testNearbyListNamesEveryPlaceWithItsDistance() async {
        let search = RecordingPlaceSearch(hits: [hit("REWE", 590), hit("REWE Center", 8200)])
        let outcome = await PlaceFlowRunner(search: search, model: "qwen3.8-flash")
            .run(.nearby, terms: ["REWE", "Supermarkt"], wish: "", mode: .walking)
        XCTAssertEqual(outcome.text, "Near you\n- REWE · 590 m away\n- REWE Center · 8 km away")
        XCTAssertEqual(search.calls, ["places:REWE,Supermarkt|"])
        XCTAssertEqual(outcome.places.map(\.name), ["REWE", "REWE Center"])
    }

    func testRouteListStaysCleanBecauseDistancesMeanNothingForADrivingPlan() async {
        let search = RecordingPlaceSearch(hits: [hit("Torstraße 1", 590)])
        let outcome = await PlaceFlowRunner(search: search, model: nil)
            .run(.route, terms: ["Torstraße 1"], wish: "", mode: .driving)
        XCTAssertEqual(outcome.text, "Route\n- Torstraße 1")
        XCTAssertEqual(search.calls, ["route:Torstraße 1|"])
    }

    func testTheUsersOwnWordsReachTheSearch() async {
        let search = RecordingPlaceSearch(hits: [hit("Frankfurter Straße 34", nil)])
        _ = await PlaceFlowRunner(search: search, model: nil)
            .run(.route, terms: ["Bismarckstraße 15"], wish: "Route nach Frankfurter Straße 34", mode: .automatic)
        XCTAssertEqual(search.calls, ["route:Bismarckstraße 15|Route nach Frankfurter Straße 34"])
    }

    func testTheNearbyOutcomeCarriesTheHeadingOfItsOwnList() async {
        let search = RecordingPlaceSearch(hits: [hit("REWE", 590)])
        let outcome = await PlaceFlowRunner(search: search, model: nil)
            .run(.nearby, terms: ["REWE"], wish: "", mode: .walking)
        XCTAssertEqual(outcome.headingKey, "place_head")
    }

    func testTheRouteOutcomeCarriesTheHeadingOfItsOwnList() async {
        let search = RecordingPlaceSearch(hits: [hit("Torstraße 1", nil)])
        let outcome = await PlaceFlowRunner(search: search, model: nil)
            .run(.route, terms: ["Torstraße 1"], wish: "", mode: .walking)
        XCTAssertEqual(outcome.headingKey, "route_head")
    }

    func testAFailureStillCarriesTheHeadingOfItsOwnList() async {
        let search = RecordingPlaceSearch(hits: [], failure: APIError(message: "boom"))
        let outcome = await PlaceFlowRunner(search: search, model: nil)
            .run(.route, terms: ["Ziel"], wish: "", mode: .walking)
        XCTAssertTrue(outcome.hits.isEmpty)
        XCTAssertEqual(outcome.headingKey, "route_head")
    }

    func testLocationFailureKeepsItsOwnMessage() async {
        let search = RecordingPlaceSearch(hits: [], failure: APIError(message: L.t("place_denied")))
        let outcome = await PlaceFlowRunner(search: search, model: nil)
            .run(.nearby, terms: ["REWE"], wish: "", mode: .walking)
        XCTAssertEqual(outcome.text, AnswerError.marker + L.t("place_denied"))
    }

    func testSearchFailureBecomesTheKindSpecificMessage() async {
        let search = RecordingPlaceSearch(hits: [], failure: APIError(message: "boom"))
        let nearby = await PlaceFlowRunner(search: search, model: nil)
            .run(.nearby, terms: ["REWE"], wish: "", mode: .walking)
        XCTAssertTrue(nearby.text.hasPrefix("⚠️ No matching place was found nearby."), nearby.text)
        XCTAssertTrue(nearby.hits.isEmpty)
        let route = await PlaceFlowRunner(search: search, model: nil)
            .run(.route, terms: ["Ziel"], wish: "", mode: .automatic)
        XCTAssertTrue(route.text.contains("That address was not found."), route.text)
    }
}
