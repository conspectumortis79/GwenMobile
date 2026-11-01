@testable import GwenMobileFeatureCore
import Foundation
import GwenMobileKit
@testable import GwenMobileProbes

enum WeatherFixture {
    static func hour(_ hour: Int, temp: Double = 15, rain: Int = 0, precip: Double = 0,
                     wind: Double = 10, gust: Double = 20, uv: Double = 1,
                     kind: WeatherKind = .cloud) -> WeatherHour {
        WeatherHour(hour: hour, temp: temp, rain: rain, precip: precip, wind: wind, gust: gust,
                    uv: uv, kind: kind)
    }

    static func ref(place: String = "München",
                    hours: [WeatherHour]) -> WeatherRef {
        WeatherRef(place: place, latitude: 48.137, longitude: 11.575, day: "2026-10-05",
                   timezone: "Europe/Berlin", hours: hours)
    }

    static func day(_ body: (Int) -> WeatherHour) -> [WeatherHour] {
        (6...22).map(body)
    }

    @MainActor
    static func service() -> WeatherService {
        WeatherService.clearCache()
        var service = WeatherService()
        service.fetcher = { _ in ForecastFixture.json(date: "2026-10-05") }
        service.geocodeAddress = { _ in
            WeatherPlace(name: "Berlin", latitude: 52.52, longitude: 13.405, timezone: "Europe/Berlin")
        }
        service.localSearch = { _ in
            WeatherPlace(name: "Berlin", latitude: 52.52, longitude: 13.405, timezone: "Europe/Berlin")
        }
        service.reverseGeocode = { _ in "Berlin" }
        return service
    }
}
