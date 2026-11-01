@testable import GwenMobileFeatureCore
import GwenMobileKit
import CoreLocation
import Foundation
import MapKit

@MainActor
struct CoreLocationPlaceLookup: ReminderPlaceLooking {
    func locate(_ name: String) async -> GeoPoint? {
        let wanted = name.trimmed
        guard !wanted.isEmpty,
              let request = MKGeocodingRequest(addressString: wanted),
              let item = try? await request.mapItems.first else { return nil }
        let coordinate = item.location.coordinate
        return GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude,
                        radius: ReminderPlaceRadius.fitting(region: nil))
    }
}

@MainActor
struct NearbyReminderPlaceLookup: ReminderPlaceLooking {
    static let reach: Double = 50_000

    let search: any NearbyPlacing

    init(search: any NearbyPlacing = LivePlaceSearch()) {
        self.search = search
    }

    func locate(_ name: String) async -> GeoPoint? {
        let wanted = name.trimmed
        guard !wanted.isEmpty else { return nil }
        let hits = (try? await search.places(matching: [wanted], wish: wanted, mode: .walking)) ?? []
        guard let hit = hits.first(where: { Double($0.place.metres ?? Int.max) <= Self.reach }),
              let latitude = hit.place.latitude, let longitude = hit.place.longitude else { return nil }
        return GeoPoint(latitude: latitude, longitude: longitude, radius: ReminderPlaceRadius.narrow)
    }
}

@MainActor
enum ReminderSystem {
    static func install() {
        ReminderPlacePort.current = ReminderPlaceLookupChain(first: NearbyReminderPlaceLookup(),
                                                            second: CoreLocationPlaceLookup())
    }
}
