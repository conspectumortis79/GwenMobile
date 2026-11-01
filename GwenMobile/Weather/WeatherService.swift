import GwenMobileKit
import CoreLocation
import Foundation
import MapKit

@MainActor
struct WeatherService {
    static let cacheLifetime: TimeInterval = 20 * 60
    static let cacheLimit = 32

    struct Cached: Sendable {
        let at: Date
        let ref: WeatherRef
    }

    static let cache = LockedValue([String: Cached]())

    var fixer: any LocationFixing = LiveLocationFix()
    var fetcher: @Sendable (URLRequest) async throws -> Data = { try await HTTP.jsonData($0) }
    var timeout: TimeInterval = 20
    @MainActor var geocodeAddress: (String) async -> WeatherPlace? = WeatherService.defaultGeocode
    @MainActor var localSearch: (String) async -> WeatherPlace? = WeatherService.defaultLocalSearch
    @MainActor var reverseGeocode: (CLLocation) async -> String? = WeatherService.defaultReverseGeocode

    nonisolated(unsafe) static var defaultGeocode: @MainActor (String) async -> WeatherPlace? = { _ in nil }
    nonisolated(unsafe) static var defaultLocalSearch: @MainActor (String) async -> WeatherPlace? = { _ in nil }
    nonisolated(unsafe) static var defaultReverseGeocode: @MainActor (CLLocation) async -> String? = { _ in nil }
    nonisolated(unsafe) static var forecastURL: @Sendable (WeatherPlace, String) -> URL? = OpenMeteo.forecastURL

    func day(for request: WeatherRequest, now: Date = Date(),
             calendar: Calendar = .current) async throws -> WeatherRef {
        let date = targetDate(request, now: now, calendar: calendar)
        let trimmed = request.place?.trimmed
        if let name = trimmed, !name.isEmpty {
            guard let place = await resolved(name) else {
                throw APIError(message: L.fmt("weather_place_missing", name))
            }
            return try await day(place: place, date: date, now: now)
        }
        let location: CLLocation
        do {
            location = try await fixer.fix()
        } catch {
            throw APIError(message: L.t("weather_location_needed"))
        }
        let place = WeatherPlace(name: await cityName(location) ?? L.t("weather_here"),
                                 latitude: location.coordinate.latitude,
                                 longitude: location.coordinate.longitude,
                                 timezone: TimeZone.current.identifier)
        return try await day(place: place, date: date, now: now)
    }

    func day(place: WeatherPlace, date: String, now: Date = Date()) async throws -> WeatherRef {
        let key = Self.cacheKey(place: place, date: date)
        if let hit = Self.cached(key, now: now) { return hit }
        guard let url = Self.forecastURL(place, date) else {
            throw APIError(message: L.t("weather_data_missing"))
        }
        let data = try await fetcher(URLRequest(url: url, timeoutInterval: timeout))
        guard let ref = OpenMeteo.day(from: data, date: date, place: place) else {
            throw APIError(message: L.t("weather_data_missing"))
        }
        Self.remember(ref, key: key, now: now)
        return ref
    }

    static func cacheKey(place: WeatherPlace, date: String) -> String {
        "\(date)|\(place.name.lowercased())|\(place.latitude)|\(place.longitude)"
    }

    static func cached(_ key: String, now: Date) -> WeatherRef? {
        guard let hit = cache.current[key], now.timeIntervalSince(hit.at) < cacheLifetime else { return nil }
        return hit.ref
    }

    static func remember(_ ref: WeatherRef, key: String, now: Date) {
        cache.mutate { stored in
            stored[key] = Cached(at: now, ref: ref)
            while stored.count > cacheLimit, let oldest = stored.min(by: { $0.value.at < $1.value.at })?.key {
                stored[oldest] = nil
            }
        }
    }

    func targetDate(_ request: WeatherRequest, now: Date, calendar: Calendar) -> String {
        if let raw = request.date, let parsed = Formatters.eventDay(from: raw) {
            if let offset = request.offset {
                let derived = request.daysAhead(from: now, calendar: calendar)
                if derived != offset {
                    flowMarkPersonal("WETTER datum abweichung datum=\(Formatters.stamp(parsed)) "
                                     + "zaehler=+\(offset)d gerechnet=\(derived.map { "+\($0)d" } ?? "-")")
                }
            }
            return Formatters.stamp(parsed)
        }
        let days = request.offset ?? request.day.index
        let date = calendar.date(byAdding: .day, value: days, to: now)!
        return Formatters.stamp(date)
    }

    private func resolved(_ name: String) async -> WeatherPlace? {
        await Self.firstPlace([
            { try await self.openMeteoPlace(name) },
            { await self.geocodedPlace(name) },
            { await self.localPlace(name) },
        ])
    }

    static func firstPlace(_ lookups: [() async throws -> WeatherPlace?]) async -> WeatherPlace? {
        for lookup in lookups {
            if let place = try? await lookup() { return place }
        }
        return nil
    }

    private func openMeteoPlace(_ name: String) async throws -> WeatherPlace? {
        guard let url = OpenMeteo.geocodeURL(name: name, language: L.lang) else { return nil }
        let data = try await fetcher(URLRequest(url: url, timeoutInterval: timeout))
        return OpenMeteo.place(from: data)
    }

    private func geocodedPlace(_ name: String) async -> WeatherPlace? {
        await geocodeAddress(name)
    }

    private func localPlace(_ name: String) async -> WeatherPlace? {
        await localSearch(name)
    }

    nonisolated static func samePlace(_ first: String, _ second: String) -> Bool {
        TextFolding.fold(first).lowercased() == TextFolding.fold(second).lowercased()
    }

    private func cityName(_ location: CLLocation) async -> String? {
        await reverseGeocode(location)
    }
}
