@testable import GwenMobileFeatureCore
import GwenMobileKit
import CoreLocation
import Foundation
import MapKit

@MainActor
enum WeatherSystem {
    static func liveGeocode(_ name: String) async -> WeatherPlace? {
        guard let request = MKGeocodingRequest(addressString: name),
              let item = try? await request.mapItems.first else { return nil }
        let coordinate = item.location.coordinate
        return WeatherPlace(name: item.addressRepresentations?.cityName ?? item.name ?? name,
                            latitude: coordinate.latitude, longitude: coordinate.longitude,
                            timezone: item.timeZone?.identifier)
    }

    @MainActor static func liveLocalSearch(_ name: String) async -> WeatherPlace? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = name
        request.resultTypes = [.address, .pointOfInterest]
        guard let response = try? await MKLocalSearch(request: request).start(),
              let item = response.mapItems.first,
              let location = PlaceSearch.coordinate(of: item) else { return nil }
        return WeatherPlace(name: item.name ?? name,
                            latitude: location.coordinate.latitude,
                            longitude: location.coordinate.longitude,
                            timezone: item.timeZone?.identifier)
    }

    @MainActor static func liveReverseGeocode(_ location: CLLocation) async -> String? {
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try? await request.mapItems.first else { return nil }
        return item.addressRepresentations?.cityName ?? item.name
    }

    static func install() {
        WeatherService.defaultGeocode = { await liveGeocode($0) }
        WeatherService.defaultLocalSearch = { await liveLocalSearch($0) }
        WeatherService.defaultReverseGeocode = { await liveReverseGeocode($0) }
    }
}
