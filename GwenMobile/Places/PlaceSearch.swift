import GwenMobileKit
import CoreLocation
import MapKit
import UIKit

extension NearbyPlace {
    nonisolated(unsafe) static var mapItemOpener: @MainActor (MKMapItem, [String: Any]) -> Bool = { item, options in
        item.openInMaps(launchOptions: options)
    }

    @MainActor func openRoute() -> Bool {
        guard let latitude, let longitude else { return openMapsURL() }
        let item = Self.mapItem(name: name, latitude: latitude, longitude: longitude)
        if NearbyPlace.mapItemOpener(item, [MKLaunchOptionsDirectionsModeKey: mode.launchOption]) {
            return true
        }
        return openMapsURL()
    }

    @MainActor static func mapItem(name: String, latitude: Double, longitude: Double) -> MKMapItem {
        let item = MKMapItem(location: CLLocation(latitude: latitude, longitude: longitude), address: nil)
        item.name = name
        return item
    }

    @MainActor private func openMapsURL() -> Bool {
        guard let url = directionsURL, UIApplication.shared.canOpenURL(url) else { return false }
        Task { await UIApplication.shared.open(url) }
        return true
    }
}

struct NearbyHit {
    let item: MKMapItem
    let place: NearbyPlace

    var candidate: PlaceCandidate {
        PlaceCandidate(label: [place.name, PlaceSearch.address(of: item)].compactMap { $0 }.joined(separator: " "),
                       metres: place.metres)
    }
}

@MainActor
protocol NearbyPlacing {
    func places(matching terms: [String], wish: String, mode: TravelMode) async throws -> [NearbyHit]
    func route(to terms: [String], wish: String, mode: TravelMode) async throws -> [NearbyHit]
}

enum PlaceSearch {
    static let resultLimit = 3
    static let termLimit = 3
    static let regionRadius: CLLocationDistance = 12_000

    static func request(for term: String, origin: CLLocation?) -> MKLocalSearch.Request {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = term
        if let origin {
            request.region = MKCoordinateRegion(center: origin.coordinate,
                                                latitudinalMeters: regionRadius,
                                                longitudinalMeters: regionRadius)
        }
        return request
    }

    static func hits(from items: [MKMapItem], around origin: CLLocation?,
                     mode: TravelMode) -> [NearbyHit] {
        let measured = items.compactMap { item -> (NearbyHit, Int)? in
            guard let location = coordinate(of: item) else { return nil }
            let metres = origin.map { Int($0.distance(from: location).rounded()) }
            let place = NearbyPlace(name: item.name ?? L.t("place_unnamed"),
                                    latitude: location.coordinate.latitude,
                                    longitude: location.coordinate.longitude,
                                    metres: metres, mode: mode)
            return (NearbyHit(item: item, place: place), metres ?? .max)
        }
        return measured.sorted { $0.1 < $1.1 }.prefix(resultLimit).map { $0.0 }
    }

    static func ranked(_ hits: [NearbyHit], wish: String, byDistance: Bool) -> [NearbyHit] {
        PlaceRanking.order(hits.map(\.candidate), wish: wish, byDistance: byDistance)
            .prefix(resultLimit).map { hits[$0] }
    }

    static func address(of item: MKMapItem) -> String? { item.address?.fullAddress }

    static func coordinate(of item: MKMapItem) -> CLLocation? { item.location }
}

@MainActor
final class LivePlaceSearch: ObservableObject, NearbyPlacing {
    nonisolated(unsafe) static var searchRunner: @MainActor (MKLocalSearch.Request) async throws -> [MKMapItem] = {
        request in
        try await searchRunnerDefault(request)
    }

    static func searchRunnerDefault(_ request: MKLocalSearch.Request) async throws -> [MKMapItem] {
        try await MKLocalSearch(request: request).start().mapItems
    }

    private let fixer: any LocationFixing

    init(fixer: any LocationFixing = LiveLocationFix()) {
        self.fixer = fixer
    }

    func places(matching terms: [String], wish: String, mode: TravelMode) async throws -> [NearbyHit] {
        let origin = try await fixer.fix()
        let asked = PlaceRanking.queries(terms: terms, wish: wish, limit: PlaceSearch.termLimit)
        return try await collect(asked, wish: wish, byDistance: true, mode: mode,
                                 emptyKey: "place_none_found") { term in
            try await self.lookup(PlaceSearch.request(for: term, origin: origin))
        } measured: { PlaceSearch.hits(from: $0, around: origin, mode: mode) }
    }

    func route(to terms: [String], wish: String, mode: TravelMode) async throws -> [NearbyHit] {
        let asked = PlaceRanking.queries(terms: terms, wish: wish, limit: PlaceSearch.termLimit)
        return try await collect(asked, wish: wish, byDistance: false, mode: mode,
                                 emptyKey: "route_not_found") { term in
            try await self.lookup(PlaceSearch.request(for: term, origin: nil))
        } measured: { PlaceSearch.hits(from: $0, around: nil, mode: mode) }
    }

    private func collect(_ asked: [String], wish: String, byDistance: Bool, mode: TravelMode,
                         emptyKey: String,
                         search: @escaping (String) async throws -> [MKMapItem],
                         measured: @escaping ([MKMapItem]) -> [NearbyHit]) async throws -> [NearbyHit] {
        var collected: [NearbyHit] = []
        var seen = Set<String>()
        var failure: Error?
        for term in asked {
            do {
                let response = try await search(term)
                for hit in measured(response)
                where seen.insert(hit.place.coordinateKey ?? hit.place.name).inserted {
                    collected.append(hit)
                }
            } catch {
                failure = error
                flowMarkPersonal("ORT suche begriff=\(term) fehler=keine antwort")
            }
        }
        let ranked = PlaceSearch.ranked(collected, wish: wish, byDistance: byDistance)
        flowMarkPersonal("ORT suche terms=\(asked.joined(separator: "|")) modus=\(mode.rawValue) "
                         + "gesammelt=\(collected.count) erste=\(ranked.first.map { $0.place.name } ?? "-")")
        guard !ranked.isEmpty else {
            if let failure { throw failure }
            throw APIError(message: L.t(emptyKey))
        }
        return ranked
    }

    private func lookup(_ request: MKLocalSearch.Request) async throws -> [MKMapItem] {
        try await Self.searchRunner(request)
    }
}

@MainActor
struct AppleMapsOpener: PlaceRouteOpening {
    func open(_ place: NearbyPlace) -> Bool {
        place.openRoute()
    }
}
