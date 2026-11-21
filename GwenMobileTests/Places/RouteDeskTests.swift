@testable import GwenMobileFeatureCore
import MapKit
import XCTest
import GwenMobileKit

@MainActor
final class RouteDeskTests: XCTestCase {
    @MainActor
    private final class RecordingOpener: PlaceRouteOpening {
        private(set) var opened: [NearbyPlace] = []

        func open(_ place: NearbyPlace) -> Bool {
            opened.append(place)
            return true
        }
    }

    private func place(_ name: String) -> NearbyPlace {
        NearbyPlace(name: name, latitude: 52.52, longitude: 13.4, metres: 400)
    }

    func testTheDefaultOpenerHandsOffToAppleMaps() {
        XCTAssertTrue(RouteDesk().opener is AppleMapsOpener)
    }

    func testTheProbeOpenerAnswersAndTheRestoreBringsTheDeskOpenerBack() {
        let live = RecordingOpener()
        let probe = RecordingOpener()
        let desk = RouteDesk(opener: live)
        desk.stand(in: probe)
        desk.stand(in: probe)
        desk.record([NearbyHit(item: MKMapItem(), place: place("REWE"))])
        XCTAssertTrue(desk.openRoute(for: place("REWE")))
        XCTAssertEqual(probe.opened.map(\.name), ["REWE"])
        XCTAssertTrue(live.opened.isEmpty)
        desk.restore()
        XCTAssertTrue(desk.openRoute(for: place("REWE")))
        XCTAssertEqual(live.opened.map(\.name), ["REWE"])
        desk.restore()
    }

    func testTheResetForgetsTheRecordedConversation() {
        let live = RecordingOpener()
        let desk = RouteDesk(opener: live)
        desk.record([NearbyHit(item: MKMapItem(), place: place("REWE"))])
        desk.reset()
        XCTAssertTrue(desk.openRoute(for: place("Alexanderplatz")))
        XCTAssertEqual(live.opened.first?.name, "Alexanderplatz")
    }
}
