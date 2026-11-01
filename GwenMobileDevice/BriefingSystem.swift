@testable import GwenMobileFeatureCore
import GwenMobileKit
import CoreLocation
import Foundation
import MapKit

@MainActor
struct LiveBriefingTravel: BriefingTravelLooking {
    var fixer: any LocationFixing = LiveLocationFix()

    func briefingTravel(to location: String, departure: Date) async -> DayBriefingTravel? {
        let trimmed = location.trimmed
        guard !trimmed.isEmpty, let origin = try? await fixer.fix() else { return nil }
        guard let target = try? await coordinate(of: trimmed) else { return nil }
        async let car = minutes(from: origin, to: target, type: .automobile, departure: departure)
        async let bike = minutes(from: origin, to: target, type: .cycling, departure: departure)
        let found = await (car: car, bike: bike)
        guard found.car != nil || found.bike != nil else { return nil }
        return DayBriefingTravel(title: trimmed, carMinutes: found.car, bikeMinutes: found.bike)
    }

    nonisolated(unsafe) static var geocode: @MainActor (String) async throws -> CLLocationCoordinate2D? = { place in
        try await geocodeDefault(place)
    }

    static func geocodeDefault(_ place: String) async throws -> CLLocationCoordinate2D? {
        guard let request = MKGeocodingRequest(addressString: place) else { return nil }
        return try await request.mapItems.first?.location.coordinate
    }

    nonisolated(unsafe) static var travelMinutes: @MainActor (CLLocationCoordinate2D, CLLocationCoordinate2D,
                                                              MKDirectionsTransportType, Date) async -> Int? = {
        from, to, type, departure in
        await travelMinutesDefault(from, to, type, departure)
    }

    static func travelMinutesDefault(_ from: CLLocationCoordinate2D, _ to: CLLocationCoordinate2D,
                                     _ type: MKDirectionsTransportType, _ departure: Date) async -> Int? {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: from.latitude, longitude: from.longitude),
                                   address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: to.latitude, longitude: to.longitude),
                                        address: nil)
        request.transportType = type
        request.departureDate = departure
        guard let response = try? await MKDirections(request: request).calculate(),
              let route = response.routes.first else { return nil }
        return max(1, Int((route.expectedTravelTime / 60).rounded()))
    }

    func coordinate(of place: String) async throws -> CLLocationCoordinate2D {
        guard let coordinate = try await Self.geocode(place) else {
            throw APIError(message: L.t("place_none_found"))
        }
        return coordinate
    }

    func minutes(from origin: CLLocation, to target: CLLocationCoordinate2D,
                 type: MKDirectionsTransportType, departure: Date) async -> Int? {
        await Self.travelMinutes(origin.coordinate, target, type, departure)
    }
}

@MainActor
enum BriefingSystem {
    static func install() {
        BriefingTravelPort.current = LiveBriefingTravel()
    }
}
