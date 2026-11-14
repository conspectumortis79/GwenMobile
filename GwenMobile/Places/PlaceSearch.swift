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
    func places(matching terms: [String], wish: String, mode: TravelMode,
                count: Int?) async throws -> [NearbyHit]
    func route(to terms: [String], wish: String, mode: TravelMode,
               count: Int?) async throws -> [NearbyHit]
}

enum PlaceSearch {
    static let resultLimit = 3
    static let maxResults = 10
    static let termLimit = 3

    static func normalizedCount(_ requested: Int?) -> Int {
        guard let requested, requested > 0 else { return resultLimit }
        return min(requested, maxResults)
    }

    static let regionRadius: CLLocationDistance = 12_000

    struct Area {
        let name: String
        let location: CLLocation
    }

    static func request(for term: String, origin: CLLocation?,
                        pinsRegion: Bool = false) -> MKLocalSearch.Request {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = term
        if let origin {
            request.region = MKCoordinateRegion(center: origin.coordinate,
                                                latitudinalMeters: regionRadius,
                                                longitudinalMeters: regionRadius)
            if pinsRegion {
                if #available(iOS 18.0, macOS 15.0, *) {
                    request.regionPriority = .required
                }
            }
        }
        return request
    }

    static func area(in items: [MKMapItem], wish: String) -> Area? {
        for item in items {
            guard let name = item.name, let location = coordinate(of: item),
                  PlaceWishGrounding.isGrounded(name, in: wish) else { continue }
            return Area(name: name, location: location)
        }
        return nil
    }

    static func hits(from items: [MKMapItem], around origin: CLLocation?,
                     mode: TravelMode, limit: Int = resultLimit) -> [NearbyHit] {
        let measured = items.compactMap { item -> (NearbyHit, Int)? in
            guard let location = coordinate(of: item) else { return nil }
            let metres = origin.map { Int($0.distance(from: location).rounded()) }
            let place = NearbyPlace(name: item.name ?? L.t("place_unnamed"),
                                    latitude: location.coordinate.latitude,
                                    longitude: location.coordinate.longitude,
                                    metres: metres, mode: mode)
            return (NearbyHit(item: item, place: place), metres ?? .max)
        }
        let ordered = origin == nil ? measured : measured.sorted { $0.1 < $1.1 }
        return ordered.prefix(limit).map { $0.0 }
    }

    static func ranked(_ hits: [NearbyHit], wish: String, byDistance: Bool,
                       limit: Int = resultLimit) -> [NearbyHit] {
        PlaceRanking.order(hits.map(\.candidate), wish: wish, byDistance: byDistance)
            .prefix(limit).map { hits[$0] }
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

    func places(matching terms: [String], wish: String, mode: TravelMode,
                count: Int? = nil) async throws -> [NearbyHit] {
        let limit = PlaceSearch.normalizedCount(count)
        let fixed: CLLocation?
        var fixFailure: Error?
        do {
            fixed = try await fixer.fix()
        } catch {
            fixed = nil
            fixFailure = error
        }
        let area = fixed == nil ? await self.area(for: wish) : nil
        guard let center = fixed ?? area?.location else {
            throw Self.locationFailure(fixFailure)
        }
        let asked = PlaceRanking.queries(terms: terms, wish: wish, limit: PlaceSearch.termLimit)
        return try await collect(asked, wish: wish, byDistance: true, mode: mode,
                                 limit: limit, emptyKey: "place_none_found",
                                 rejecting: area?.name, within: area?.location) { term in
            try await self.lookup(PlaceSearch.request(for: term, origin: center,
                                                      pinsRegion: area != nil))
        } measured: { PlaceSearch.hits(from: $0, around: fixed, mode: mode, limit: limit) }
    }

    private func area(for wish: String) async -> PlaceSearch.Area? {
        let trimmed = wish.trimmed
        guard !trimmed.isEmpty else { return nil }
        guard let items = try? await lookup(PlaceSearch.request(for: trimmed, origin: nil)) else {
            flowMarkPersonal("ORT flaeche begriff=\(trimmed) fehler=keine antwort")
            return nil
        }
        let found = PlaceSearch.area(in: items, wish: trimmed)
        flowMarkPersonal("ORT flaeche begriff=\(trimmed) treffer=\(found?.name ?? "-")")
        return found
    }

    private static func locationFailure(_ error: Error?) -> Error {
        if let api = error as? APIError { return api }
        return APIError(message: L.t("place_unavailable"))
    }

    func route(to terms: [String], wish: String, mode: TravelMode,
               count: Int? = nil) async throws -> [NearbyHit] {
        let limit = PlaceSearch.normalizedCount(count)
        let asked = PlaceRanking.queries(terms: terms, wish: wish, limit: PlaceSearch.termLimit)
        return try await collect(asked, wish: wish, byDistance: false, mode: mode,
                                 limit: limit, emptyKey: "route_not_found") { term in
            try await self.lookup(PlaceSearch.request(for: term, origin: nil))
        } measured: { PlaceSearch.hits(from: $0, around: nil, mode: mode, limit: limit) }
    }

    private func collect(_ asked: [String], wish: String, byDistance: Bool, mode: TravelMode,
                         limit: Int, emptyKey: String, rejecting name: String? = nil,
                         within area: CLLocation? = nil,
                         search: @escaping (String) async throws -> [MKMapItem],
                         measured: @escaping ([MKMapItem]) -> [NearbyHit]) async throws -> [NearbyHit] {
        var collected: [NearbyHit] = []
        var seen = Set<String>()
        var failure: Error?
        for term in asked {
            do {
                let response = try await search(term)
                for hit in measured(response)
                where keeps(hit, rejecting: name, within: area)
                    && seen.insert(hit.place.coordinateKey ?? hit.place.name).inserted {
                    collected.append(hit)
                }
            } catch {
                failure = error
                flowMarkPersonal("ORT suche begriff=\(term) fehler=keine antwort")
            }
        }
        let ranked = PlaceSearch.ranked(collected, wish: wish, byDistance: byDistance, limit: limit)
        flowMarkPersonal("ORT suche terms=\(asked.joined(separator: "|")) modus=\(mode.rawValue) "
                         + "gesammelt=\(collected.count) erste=\(ranked.first.map { $0.place.name } ?? "-")")
        guard !ranked.isEmpty else {
            if let api = failure as? APIError { throw api }
            if let failure {
                flowMarkPersonal("ORT suche fehler=\(failure.localizedDescription)")
            }
            throw APIError(message: L.t(emptyKey))
        }
        return ranked
    }

    private func keeps(_ hit: NearbyHit, rejecting name: String?, within area: CLLocation?) -> Bool {
        if let name, TextFolding.fold(hit.place.name) == TextFolding.fold(name) { return false }
        guard let area, let latitude = hit.place.latitude, let longitude = hit.place.longitude else {
            return true
        }
        let location = CLLocation(latitude: latitude, longitude: longitude)
        return location.distance(from: area) <= PlaceSearch.regionRadius
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
