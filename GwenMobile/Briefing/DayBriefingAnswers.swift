import GwenMobileKit
import Foundation

enum DayBriefingAnswers {
    static func closing(_ ref: DayBriefingRef) -> String {
        let overdue = ref.reminders.filter(\.overdue).count
        if ref.events.isEmpty && ref.reminders.isEmpty { return L.t("brief_closing_free") }
        if overdue > 0 {
            return L.counted(overdue, one: "brief_closing_overdue_one", many: "brief_closing_overdue")
        }
        if ref.events.count >= 3 { return L.n("brief_closing_dense", ref.events.count) }
        return L.t("brief_closing_calm")
    }

    static func eventDetail(_ event: DayBriefingEvent) -> String {
        var parts = [event.stampText]
        if let location = event.location, !location.isEmpty { parts.append(location) }
        if !event.calendar.isEmpty { parts.append(event.calendar) }
        return parts.joined(separator: " · ")
    }

    static func notificationBody(_ ref: DayBriefingRef) -> String {
        TextLine.oneLine(text(ref), limit: 260)
    }

    static func notificationTitle() -> String {
        L.t("brief_notify_title")
    }

    static func text(_ ref: DayBriefingRef) -> String {
        var parts: [String] = [ref.greeting + "."]
        var head = ref.dayText + ":"
        if ref.events.isEmpty {
            head += " " + L.t("brief_no_events")
        } else {
            let count = L.counted(ref.events.count, one: "brief_event_one", many: "brief_event_many")
            head += " " + count + ", " + L.fmt2("brief_event_first", ref.events[0].title,
                                                ref.events[0].timeText)
        }
        parts.append(head)
        if let weather = ref.weather, let line = weatherLine(weather) { parts.append(line) }
        if !ref.reminders.isEmpty {
            parts.append(L.fmt("brief_open", ref.reminders.map(\.title).joined(separator: ", ")))
        }
        if let birthday = ref.birthdays.first {
            parts.append(birthday.title + " " + birthday.detail + ".")
        }
        if !ref.closing.isEmpty { parts.append(ref.closing) }
        return parts.joined(separator: " ")
    }

    static func travelText(_ travel: DayBriefingTravel) -> String {
        var parts: [String] = []
        if let car = travel.carMinutes { parts.append(L.fmt("brief_travel_car", "\(car) min")) }
        if let bike = travel.bikeMinutes { parts.append(L.fmt("brief_travel_bike", "\(bike) min")) }
        return parts.joined(separator: " · ")
    }

    static func weatherLine(_ ref: WeatherRef) -> String? {
        guard let line = WeatherAdviceRules.rangeAndNote(for: ref) else { return nil }
        guard !line.note.isEmpty else { return line.range }
        return L.fmt2("brief_weather_line", line.range, line.note)
    }
}
