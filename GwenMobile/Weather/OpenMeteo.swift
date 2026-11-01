import GwenMobileKit
import Foundation

enum OpenMeteo {
    static let forecastBase = "https://api.open-meteo.com/v1/forecast"
    static let geocodeBase = "https://geocoding-api.open-meteo.com/v1/search"
    static let hourlyFields = "temperature_2m,precipitation_probability,precipitation,wind_speed_10m,"
        + "wind_gusts_10m,uv_index,weather_code"

    static func geocodeURL(name: String, language: AppLanguage) -> URL? {
        var components = URLComponents(string: geocodeBase)
        components?.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: language.rawValue),
            URLQueryItem(name: "format", value: "json")
        ]
        return components?.url
    }

    static func forecastURL(place: WeatherPlace, date: String) -> URL? {
        var components = URLComponents(string: forecastBase)
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(place.latitude)),
            URLQueryItem(name: "longitude", value: String(place.longitude)),
            URLQueryItem(name: "hourly", value: hourlyFields),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "start_date", value: date),
            URLQueryItem(name: "end_date", value: date)
        ]
        return components?.url
    }

    static func place(from data: Data) -> WeatherPlace? {
        guard let answer = try? JSONDecoder().decode(GeocodeAnswer.self, from: data) else { return nil }
        return answer.results?.first
    }

    static func day(from data: Data, date: String, place: WeatherPlace) -> WeatherRef? {
        guard let answer = try? JSONDecoder().decode(ForecastAnswer.self, from: data),
              let hourly = answer.hourly else { return nil }
        var hours: [WeatherHour] = []
        for index in hourly.time.indices {
            guard index < hourly.temperature.count, let temperature = hourly.temperature[index] else { continue }
            let stamp = hourly.time[index]
            guard stamp.hasPrefix(date), let hour = hour(of: stamp), (6...22).contains(hour) else { continue }
            let wind = value(hourly.wind, index)
            hours.append(WeatherHour(hour: hour,
                                     temp: temperature,
                                     rain: value(hourly.probability, index),
                                     precip: value(hourly.precipitation, index),
                                     wind: wind,
                                     gust: value(hourly.gusts, index, fallback: wind),
                                     uv: value(hourly.uv, index),
                                     kind: WeatherKind.wmo(value(hourly.code, index))))
        }
        guard hours.count >= 3 else { return nil }
        return WeatherRef(place: place.name, latitude: place.latitude, longitude: place.longitude,
                          day: date,
                          timezone: answer.timezone ?? place.timezone, hours: hours)
    }

    private static func hour(of stamp: String) -> Int? {
        guard let marker = stamp.firstIndex(of: "T") else { return nil }
        let after = stamp[stamp.index(after: marker)...]
        return Int(after.prefix(2))
    }

    private static func value<Number: Numeric>(_ list: [Number?]?, _ index: Int, fallback: Number = 0) -> Number {
        guard let list, index < list.count, let found = list[index] else { return fallback }
        return found
    }

    private struct GeocodeAnswer: Decodable {
        var results: [WeatherPlace]?
    }

    private struct ForecastAnswer: Decodable {
        struct Hourly: Decodable {
            var time: [String]
            var temperature: [Double?]
            var probability: [Int?]?
            var precipitation: [Double?]?
            var wind: [Double?]?
            var gusts: [Double?]?
            var uv: [Double?]?
            var code: [Int?]?

            enum CodingKeys: String, CodingKey {
                case time
                case temperature = "temperature_2m"
                case probability = "precipitation_probability"
                case precipitation
                case wind = "wind_speed_10m"
                case gusts = "wind_gusts_10m"
                case uv = "uv_index"
                case code = "weather_code"
            }
        }

        var timezone: String?
        var hourly: Hourly?
    }
}
