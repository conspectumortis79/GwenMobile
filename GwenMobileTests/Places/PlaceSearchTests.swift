@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import CoreLocation
import MapKit
import XCTest
import GwenMobileKit

final class PlaceSearchTests: XCTestCase {
    private func place(_ name: String, _ metres: Int?, _ lat: Double = 52.52, _ lon: Double = 13.405,
                      _ mode: TravelMode = .walking) -> NearbyPlace {
        NearbyPlace(name: name, latitude: lat, longitude: lon, metres: metres, mode: mode)
    }

    func testDistanceTextSwitchesToKilometresAboveALongStride() {
        L.apply(.de)
        XCTAssertEqual(place("REWE", 320).distanceText, "320 m entfernt")
        XCTAssertEqual(place("REWE", 949).distanceText, "949 m entfernt")
        XCTAssertEqual(place("REWE", 950).distanceText, "1 km entfernt")
        XCTAssertEqual(place("REWE", 1200).distanceText, "1 km entfernt")
        XCTAssertEqual(place("REWE", 1400).distanceText, "1 km entfernt")
        XCTAssertEqual(place("REWE", 14500).distanceText, "15 km entfernt")
        XCTAssertNil(place("REWE", nil).distanceText)
        L.apply(.en)
        XCTAssertEqual(place("REWE", 1200).distanceText, "1 km away")
    }

    func testDirectionsURLOnlyNamesAModeAppleDocumentsAsUnambiguous() throws {
        func flag(_ mode: TravelMode) -> String? {
            guard let url = try? XCTUnwrap(place("REWE", 320, 52.52, 13.405, mode).directionsURL) else {
                return nil
            }
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            return items.first { $0.name == "dirflg" }?.value
        }
        XCTAssertEqual(flag(.driving), "d")
        XCTAssertEqual(flag(.walking), "w")
        XCTAssertNil(flag(.transit))
        XCTAssertNil(flag(.cycling))
        XCTAssertNil(flag(.automatic))
    }

    func testDirectionsURLCarriesTheCoordinatesAndWalkingMode() throws {
        let url = try XCTUnwrap(place("REWE Mitte", 320, 52.52, 13.405).directionsURL)
        XCTAssertEqual(url.host, "maps.apple.com")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "daddr" }?.value, "52.520000,13.405000")
        XCTAssertEqual(items.first { $0.name == "dirflg" }?.value, "w")
        XCTAssertEqual(items.first { $0.name == "q" }?.value, "REWE Mitte")
    }

    func testANamedDestinationBecomesItsOwnRouteWithTheTravelModeTheUserGave() throws {
        let body = #"{"choices":[{"message":{"tool_calls":[{"id":"c","function":{"name":"route_to_place","arguments":"{\"destination\":\"Banana 13, 12345\",\"terms\":[\"Banana 13\",\"Banana\"],\"mode\":\"transit\"}"}}]}}]}"#
        let decision = try XCTUnwrap(ToolRouter.decisions(from: Data(body.utf8)).first)
        XCTAssertEqual(decision.route, .routeToPlace(terms: ["Banana 13, 12345", "Banana 13", "Banana"], mode: .transit))
        XCTAssertEqual(decision.searchQuery, "Banana 13, 12345")
    }

    func testAnUnknownTravelModeFallsBackToTheMapsDefault() {
        let body = #"{"choices":[{"message":{"tool_calls":[{"id":"c","function":{"name":"route_to_place","arguments":"{\"destination\":\"Hauptbahnhof\",\"terms\":[],\"mode\":\"helicopter\"}"}}]}}]}"#
        XCTAssertEqual(ToolRouter.decisions(from: Data(body.utf8)).first?.route,
                       .routeToPlace(terms: ["Hauptbahnhof"], mode: .automatic))
    }

    func testEveryTravelModeHasItsOwnHandoffForMaps() {
        XCTAssertEqual(TravelMode.walking.mapsURLFlag, "w")
        XCTAssertEqual(TravelMode.driving.mapsURLFlag, "d")
        XCTAssertNil(TravelMode.transit.mapsURLFlag)
        XCTAssertNil(TravelMode.cycling.mapsURLFlag)
        XCTAssertNil(TravelMode.automatic.mapsURLFlag)
        XCTAssertEqual(TravelMode.cycling.launchOption, MKLaunchOptionsDirectionsModeCycling)
        XCTAssertEqual(TravelMode.transit.launchOption, MKLaunchOptionsDirectionsModeTransit)
        XCTAssertEqual(TravelMode.driving.launchOption, MKLaunchOptionsDirectionsModeDriving)
        XCTAssertEqual(TravelMode.automatic.launchOption, MKLaunchOptionsDirectionsModeDefault)
    }

    func testPlaceWithoutCoordinatesHasNoHandoffURL() {
        XCTAssertNil(NearbyPlace(name: "REWE", latitude: nil, longitude: nil, metres: nil).directionsURL)
    }

    func testPlacesSurviveTheConversationRoundTripAndOldMessagesStillDecode() throws {
        var message = ChatMessage(role: .assistant, text: "In deiner Nähe")
        message.placeGroups = [PlaceGroup(headingKey: "place_head", places: [place("REWE", 320)])]
        let data = try JSONEncoder().encode([message])
        XCTAssertEqual(try JSONDecoder().decode([ChatMessage].self, from: data).first?.allPlaces.first?.name, "REWE")

        let legacy = #"[{"id":"6E2A1C4D-5B7F-4A10-9C8D-0E1F2A3B4C5D","role":"assistant","text":"alt","images":[],"date":800000000}]"#
        let decoded = try JSONDecoder().decode([ChatMessage].self, from: Data(legacy.utf8))
        XCTAssertNil(decoded.first?.placeGroups)
    }

    func testThePlaceToolIsOfferedAndMapsOntoItsOwnRoute() throws {
        let names = ToolRouter.tools(attachable: false).compactMap {
            ($0["function"] as? [String: Any])?["name"] as? String
        }
        XCTAssertTrue(names.contains(ToolRouter.placeTool))
        let body = #"{"choices":[{"message":{"tool_calls":[{"id":"c","function":{"name":"find_nearby_place","arguments":"{\"query\":\"REWE Supermarkt\",\"terms\":[\"REWE Supermarkt\",\"REWE\"],\"mode\":\"cycling\"}"}}]}}]}"#
        let decision = try XCTUnwrap(ToolRouter.decisions(from: Data(body.utf8)).first)
        XCTAssertEqual(decision.route, .nearbyPlace(terms: ["REWE Supermarkt", "REWE"], mode: .cycling))
        XCTAssertEqual(decision.searchQuery, "REWE Supermarkt")
    }

    func testThePlaceToolAsksForSearchTermsBecauseAppleMatchesNarrowly() throws {
        let tool = ToolRouter.tools(attachable: false).first {
            ($0["function"] as? [String: Any])?["name"] as? String == ToolRouter.placeTool
        }
        let parameters = (tool?["function"] as? [String: Any])?["parameters"] as? [String: Any]
        XCTAssertEqual(parameters?["required"] as? [String], ["query", "terms"])
        let properties = parameters?["properties"] as? [String: Any]
        XCTAssertEqual((properties?["terms"] as? [String: Any])?["type"] as? String, "array")
    }

    func testNearestPlaceWinsAndTheListStopsAtTheLimit() {
        let items = [MKMapItem(), MKMapItem(), MKMapItem()]
        let hits = [
            NearbyHit(item: items[0], place: place("REWE Center", 8000)),
            NearbyHit(item: items[1], place: place("REWE", 590)),
            NearbyHit(item: items[2], place: place("REWE City", 1200)),
        ]
        XCTAssertEqual(PlaceSearch.ranked(hits, wish: "", byDistance: true).map(\.place.name),
                       ["REWE", "REWE City", "REWE Center"])
        XCTAssertEqual(PlaceSearch.ranked(hits + hits, wish: "", byDistance: true).count, PlaceSearch.resultLimit)
    }

    func testPlaceWithoutCoordinatesStillHandsOffThroughTheStoredItem() {
        let far = place("REWE", nil, 0, 0)
        XCTAssertNotNil(NearbyHit(item: MKMapItem(), place: far).place.name)
    }

    private func mapItem(_ name: String, _ lat: Double, _ lon: Double) -> MKMapItem {
        let item = MKMapItem(location: CLLocation(latitude: lat, longitude: lon), address: nil)
        item.name = name
        return item
    }

    func testAMapItemCarriesItsCoordinate() throws {
        let item = mapItem("REWE", 52.52, 13.405)
        let current = try XCTUnwrap(PlaceSearch.coordinate(of: item))
        XCTAssertEqual(current.coordinate.latitude, 52.52, accuracy: 0.0001)
        XCTAssertEqual(current.coordinate.longitude, 13.405, accuracy: 0.0001)
    }

    func testHitsMeasureEveryItemThatCarriesACoordinateAndStopAtTheLimit() {
        let origin = CLLocation(latitude: 52.52, longitude: 13.405)
        let items = [mapItem("Weit", 52.60, 13.405), mapItem("Nah", 52.521, 13.405),
                     mapItem("Mittig", 52.55, 13.405), mapItem("Vierte", 52.56, 13.405)]
        let hits = PlaceSearch.hits(from: items, around: origin, mode: .walking)
        XCTAssertEqual(hits.map(\.place.name), ["Nah", "Mittig", "Vierte"])
        XCTAssertEqual(hits.count, PlaceSearch.resultLimit)
        XCTAssertEqual(hits.map(\.place.mode), Array(repeating: .walking, count: PlaceSearch.resultLimit))
        XCTAssertNotNil(hits.first?.place.distanceText)
    }
}
