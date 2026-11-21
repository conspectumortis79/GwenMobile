@testable import GwenMobileFeatureCore
import MapKit
import XCTest
import GwenMobileKit

@MainActor
final class RouteHitRegistryTests: XCTestCase {
    private func hit(_ name: String, _ latitude: Double) -> NearbyHit {
        NearbyHit(item: MKMapItem(),
                  place: NearbyPlace(name: name, latitude: latitude, longitude: 13.4, metres: 400))
    }

    func testRecordingKeepsExactlyThePlacesThatWereFound() {
        var registry = RouteHitRegistry()
        let rewe = hit("REWE", 52.52)
        registry.record([rewe])
        XCTAssertNotNil(registry.hit(for: rewe.place))
        XCTAssertNil(registry.hit(for: hit("Anderer Ort", 52.51).place))
    }

    func testTheSamePlaceRecordedTwiceIsHeldOnce() {
        var registry = RouteHitRegistry()
        let rewe = hit("REWE", 52.52)
        registry.record([rewe, rewe])
        for index in 1..<RouteHitRegistry.capacity {
            registry.record([hit("Nr \(index)", Double(index))])
        }
        XCTAssertNotNil(registry.hit(for: rewe.place),
                        "ein doppelt gemeldeter Ort belegt nur einen Platz und fällt nicht vorzeitig heraus")
    }

    func testResetDropsEverythingARecordedConversationHeld() {
        var registry = RouteHitRegistry()
        let rewe = hit("REWE", 52.52)
        registry.record([rewe])
        registry.reset()
        XCTAssertNil(registry.hit(for: rewe.place))
    }

    func testTheRegistryStaysBoundedWhenManyPlacesArrive() {
        var registry = RouteHitRegistry()
        for index in 0..<60 {
            registry.record([hit("Nr \(index)", Double(index))])
        }
        let oldestKept = 60 - RouteHitRegistry.capacity
        XCTAssertNotNil(registry.hit(for: hit("Nr 59", 59).place))
        XCTAssertNotNil(registry.hit(for: hit("Nr \(oldestKept)", Double(oldestKept)).place))
        XCTAssertNil(registry.hit(for: hit("Nr \(oldestKept - 1)", Double(oldestKept - 1)).place))
        XCTAssertNil(registry.hit(for: hit("Nr 0", 0).place))
    }

    func testOpeningARouteWithoutCoordinatesStaysFalse() {
        let registry = RouteHitRegistry()
        XCTAssertFalse(registry.openRoute(for: NearbyPlace(name: "ohne", latitude: nil, longitude: nil,
                                                           metres: nil, mode: .walking)) { $0.openRoute() })
    }

    func testTheStoredHitWinsTheOpener() {
        var registry = RouteHitRegistry()
        let known = hit("REWE", 52.5)
        registry.record([known])
        let opened = LockedValue<[String]>([])
        XCTAssertTrue(registry.openRoute(for: known.place) { place in
            opened.mutate { $0.append(place.name) }
            return true
        })
        XCTAssertEqual(opened.current, ["REWE"])
    }

    func testWithoutAHitTheAskedPlaceReachesTheOpener() {
        let registry = RouteHitRegistry()
        let asked = NearbyPlace(name: "neu", latitude: 1, longitude: 2, metres: nil, mode: .walking)
        let opened = LockedValue<[String]>([])
        XCTAssertTrue(registry.openRoute(for: asked) { place in
            opened.mutate { $0.append(place.name) }
            return true
        })
        XCTAssertEqual(opened.current, ["neu"])
    }
}
