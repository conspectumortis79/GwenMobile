import Foundation

@MainActor
struct RouteHitRegistry {
    static let capacity = 40

    private var hits: [NearbyPlace: NearbyHit] = [:]
    private var order: [NearbyPlace] = []

    mutating func record(_ newHits: [NearbyHit]) {
        for hit in newHits {
            if hits[hit.place] == nil {
                order.append(hit.place)
            }
            hits[hit.place] = hit
        }
        while order.count > Self.capacity {
            hits[order.removeFirst()] = nil
        }
    }

    func hit(for place: NearbyPlace) -> NearbyHit? {
        hits[place]
    }

    func openRoute(for place: NearbyPlace, opened: (NearbyPlace) -> Bool) -> Bool {
        opened(hit(for: place)?.place ?? place)
    }

    mutating func reset() {
        hits = [:]
        order = []
    }
}
