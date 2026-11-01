import Foundation

@MainActor
protocol PlaceRouteOpening {
    func open(_ place: NearbyPlace) -> Bool
}

@MainActor
final class RouteDesk: ObservableObject {
    private(set) var hits = RouteHitRegistry()
    private(set) var opener: any PlaceRouteOpening

    init(opener: any PlaceRouteOpening = AppleMapsOpener()) {
        self.opener = opener
    }

    func record(_ newHits: [NearbyHit]) {
        hits.record(newHits)
    }

    func reset() {
        hits.reset()
    }

    func openRoute(for place: NearbyPlace) -> Bool {
        hits.openRoute(for: place) { opener.open($0) }
    }

    #if DEBUG
    private var standIn = DeskStandIn<any PlaceRouteOpening>()

    func stand(in opener: any PlaceRouteOpening) {
        standIn.stand(opener, over: &self.opener)
    }

    func restore() {
        standIn.restore(&opener)
    }
    #endif
}
