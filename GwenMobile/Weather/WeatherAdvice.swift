import GwenMobileKit
import Foundation

struct WeatherAdvice: Equatable, Sendable {
    enum Level: Int, Comparable, Sendable {
        case green = 0
        case blue = 1
        case orange = 2
        case red = 3

        static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    var level: Level
    var symbol: String
    var title: String
    var detail: String
}

enum WeatherAdviceRules {
    static func advice(for ref: WeatherRef) -> [WeatherAdvice] {
        let hours = ref.hours
        guard !hours.isEmpty else { return [] }
        var rainMax = 0
        var rainSum = 0.0
        var uvMax = 0.0
        var gustMax = 0.0
        var tempMax = 0.0
        for hour in hours {
            rainMax = max(rainMax, hour.rain)
            rainSum += hour.precip
            uvMax = max(uvMax, hour.uv)
            gustMax = max(gustMax, hour.gust)
            tempMax = max(tempMax, hour.temp)
        }
        rainSum = (rainSum * 10).rounded() / 10
        let storm = hours.contains { $0.kind.isStorm }
        let heavy = hours.contains { $0.kind.isHeavy }
        var out: [WeatherAdvice] = []
        if storm || heavy || gustMax >= 90 || rainSum >= 25 {
            out.append(WeatherAdvice(level: .red, symbol: "exclamationmark.triangle.fill",
                                     title: L.t("weather_advice_storm"),
                                     detail: (storm || heavy)
                                         ? L.t("weather_advice_storm_detail")
                                         : L.fmt("weather_advice_gust_detail", number(gustMax))))
        }
        if gustMax >= 60 {
            out.append(WeatherAdvice(level: .orange, symbol: "wind",
                                     title: L.t("weather_advice_wind"),
                                     detail: L.fmt("weather_advice_wind_detail", number(gustMax))))
        }
        if let window = rainWindow(ref) {
            out.append(WeatherAdvice(level: .blue, symbol: "umbrella.fill",
                                     title: L.t("weather_advice_umbrella"),
                                     detail: L.fmt2("weather_advice_umbrella_detail", window,
                                                    number(rainMax))))
        } else if let window = possibleWindow(ref) {
            let detail = rainMax >= 25
                ? L.fmt2("weather_advice_rain_possible_detail", window, number(rainMax))
                : L.fmt2("weather_advice_rain_possible_amount", window, number(rainSum))
            out.append(WeatherAdvice(level: .blue, symbol: "cloud.drizzle.fill",
                                     title: L.t("weather_advice_rain_possible"), detail: detail))
        }
        if tempMax >= 30 {
            out.append(WeatherAdvice(level: .orange, symbol: "thermometer.sun.fill",
                                     title: L.t("weather_advice_heat"),
                                     detail: L.fmt("weather_advice_heat_detail", number(tempMax))))
        }
        if uvMax >= 3, let window = uvWindow(ref) {
            let detail: String
            if uvMax >= 8 {
                detail = L.fmt2("weather_advice_uv_extreme_detail", number(uvMax), window)
            } else if uvMax >= 6 {
                detail = L.fmt2("weather_advice_uv_high_detail", number(uvMax), window)
            } else {
                detail = L.fmt2("weather_advice_uv_detail", number(uvMax), window)
            }
            out.append(WeatherAdvice(level: .orange, symbol: "sun.max.trianglebadge.exclamationmark",
                                     title: L.t("weather_advice_uv"), detail: detail))
        }
        if out.isEmpty {
            out.append(WeatherAdvice(level: .green, symbol: "checkmark.circle.fill",
                                     title: L.t("weather_advice_clear"),
                                     detail: L.fmt("weather_advice_clear_detail", number(uvMax))))
        }
        return out
    }

    static func summary(for ref: WeatherRef) -> String {
        let hours = ref.hours
        guard !hours.isEmpty else { return "" }
        if hours.contains(where: { $0.kind.isStorm }) { return L.t("weather_sum_storm") }
        if hours.contains(where: { $0.kind == .snow }) { return L.t("weather_sum_snow") }
        let wet = hours.filter { $0.kind.isWet || $0.rain >= 40 }
        if !wet.isEmpty {
            let early = wet.filter { $0.hour < 13 }.count
            if early == 0 { return L.t("weather_sum_rain_afternoon") }
            if early == wet.count { return L.t("weather_sum_rain_morning") }
            return L.t("weather_sum_rain_spread")
        }
        var hottest = 0.0
        for hour in hours { hottest = max(hottest, hour.temp) }
        if hottest >= 30 { return L.t("weather_sum_heat") }
        let sun = hours.filter { $0.kind == .sun }.count
        if sun >= max(3, hours.count / 2) { return L.t("weather_sum_sun") }
        if sun > 1 { return L.t("weather_sum_mixed") }
        return L.t("weather_sum_cloudy")
    }

    static func rainWindow(_ ref: WeatherRef) -> String? {
        window(ref.hours.filter { $0.rain >= 40 || ($0.precip >= 1 && $0.rain >= 30) }, ref)
    }

    static func possibleWindow(_ ref: WeatherRef) -> String? {
        window(ref.hours.filter { $0.rain >= 25 || $0.precip >= 0.3 }, ref)
    }

    private static func window(_ hours: [WeatherHour], _ ref: WeatherRef) -> String? {
        guard let first = hours.first?.hour, let last = hours.last?.hour,
              let lastPossible = ref.hours.last?.hour else { return nil }
        return windowText(first: first, last: last, lastPossible: lastPossible)
    }

    static func uvWindow(_ ref: WeatherRef) -> String? {
        window(ref.hours.filter { $0.uv >= 3 }, ref)
    }

    private static func windowText(first: Int, last: Int, lastPossible: Int) -> String {
        if first == last { return L.fmt("weather_window_hour", String(first)) }
        if last >= lastPossible { return L.fmt("weather_window_from", String(first)) }
        return L.fmt2("weather_window_range", String(first), String(last))
    }

    static func number(_ value: Double) -> String {
        guard let rounded = Int(exactly: value.rounded()) else { return "–" }
        return String(rounded)
    }

    static func number(_ value: Int) -> String {
        String(value)
    }

    static func rangeAndNote(for ref: WeatherRef) -> (range: String, note: String)? {
        let temps = ref.hours.map(\.temp)
        guard let low = temps.min(), let high = temps.max() else { return nil }
        let range = number(low) + "–" + number(high) + " °C"
        guard let note = advice(for: ref).first?.title else { return nil }
        return (range, note)
    }
}
