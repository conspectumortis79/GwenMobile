import GwenMobileKit
import Foundation

enum WeatherAnswers {
    nonisolated(unsafe) static var dayOffset: @Sendable (Calendar, Date, Date) -> Int? = { calendar, today, start in
        calendar.dateComponents([.day], from: today, to: start).day
    }

    static func dayTitle(_ dateString: String, today: Date = Date()) -> String {
        guard let date = Formatters.eventDay(from: dateString) else { return dateString }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let todayStart = calendar.startOfDay(for: today)
        guard let offset = dayOffset(calendar, todayStart, start) else {
            return dateString
        }
        if offset == 0 { return L.t("weather_today") }
        if offset == 1 { return L.t("weather_tomorrow") }
        return tabLabel(start)
    }

    static func tabLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = L.lang.locale
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return formatter.string(from: date)
    }

    static func text(ref: WeatherRef, advice: [WeatherAdvice], today: Date = Date()) -> String {
        let hours = ref.hours
        var lo = 0.0
        var hi = 0.0
        for (index, hour) in hours.enumerated() {
            if index == 0 || hour.temp < lo { lo = hour.temp }
            if index == 0 || hour.temp > hi { hi = hour.temp }
        }
        let loText = WeatherAdviceRules.number(lo)
        let hiText = WeatherAdviceRules.number(hi)
        var text = L.fmt2("weather_intro_head", dayTitle(ref.day, today: today), ref.place)
            + " " + L.fmt2("weather_temp_range", loText, hiText) + ". " + WeatherAdviceRules.summary(for: ref)
        guard let first = advice.first else { return text }
        let separator = first.title.contains(":") ? " — " : ": "
        text += " " + first.title + separator + first.detail + "."
        let hasUmbrella = advice.contains { $0.symbol == "umbrella.fill" }
        if hasUmbrella, first.symbol != "umbrella.fill", let window = WeatherAdviceRules.rainWindow(ref) {
            var rainTop = 0
            for hour in hours { rainTop = max(rainTop, hour.rain) }
            text += " " + L.fmt2("weather_umbrella_line", window,
                                 WeatherAdviceRules.number(rainTop))
        }
        var gusts = 0.0
        for hour in hours { gusts = max(gusts, hour.gust) }
        if gusts >= 60, first.symbol != "wind", first.symbol != "exclamationmark.triangle.fill" {
            text += " " + L.fmt("weather_wind_line", WeatherAdviceRules.number(gusts))
        }
        return text
    }

    static func hourLine(_ ref: WeatherRef, hour: Int) -> String {
        guard let item = ref.hours.first(where: { $0.hour == hour }) else { return "" }
        return [L.fmt("weather_hour_time", String(item.hour)),
                L.fmt("weather_temp_short", WeatherAdviceRules.number(item.temp)),
                L.fmt("weather_rain_short", String(item.rain)),
                L.fmt("weather_gust_short", WeatherAdviceRules.number(item.gust)),
                L.fmt("weather_uv_short", WeatherAdviceRules.number(item.uv))].joined(separator: " · ")
    }
}
