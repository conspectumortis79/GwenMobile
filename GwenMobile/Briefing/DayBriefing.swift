import GwenMobileKit
import Foundation

typealias BriefingDay = DayChoice

extension DayChoice {
    var titleKey: String {
        switch self {
        case .today: return "brief_day_today"
        case .tomorrow: return "brief_day_tomorrow"
        case .dayAfter: return "brief_day_after"
        }
    }

    var title: String { L.t(titleKey) }

    static func at(offset: Int) -> DayChoice { at(index: offset) }

    static func between(_ start: Date, and date: Date, calendar: Calendar = .current) -> BriefingDay? {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start),
                                           to: calendar.startOfDay(for: date)).day!
        guard (0...2).contains(days) else { return nil }
        return at(offset: days)
    }
}

struct DayBriefingRequest: Equatable, Sendable {
    var day: BriefingDay = .today

    var stepWords: String { day.rawValue }
}

struct DayBriefingIncludes: Equatable, Sendable {
    var weather = true
    var reminders = true
    var birthdays = true
    var travel = true
}

struct DayBriefingEvent: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var title: String
    var start: Date
    var end: Date?
    var allDay: Bool
    var location: String?
    var calendar: String
    var ref: CalendarRef?

    enum CodingKeys: String, CodingKey {
        case id, title, start, end, allDay, location, calendar, ref
    }

    init(id: String, title: String, start: Date, end: Date? = nil, allDay: Bool = false,
         location: String? = nil, calendar: String = "", ref: CalendarRef? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.allDay = allDay
        self.location = location
        self.calendar = calendar
        self.ref = ref
    }

    init(from decoder: Decoder) throws {
        let fields = try LenientFields<CodingKeys>(decoder)
        id = fields.content(String.self, .id, fallback: "")
        title = fields.content(String.self, .title, fallback: "")
        start = fields.metadata(Date.self, .start, fallback: Date(timeIntervalSince1970: 0))
        end = fields.metadata(Date.self, .end)
        allDay = fields.metadata(Bool.self, .allDay, fallback: false)
        location = fields.metadata(String.self, .location)
        calendar = fields.metadata(String.self, .calendar, fallback: "")
        ref = fields.content(CalendarRef.self, .ref).flatMap { $0.isOpenable ? $0 : nil }
    }

    var timeText: String {
        allDay ? L.t("brief_all_day") : Formatters.time(start)
    }

    var stampText: String {
        guard let end, !allDay else { return timeText }
        return Formatters.time(start) + "–" + Formatters.time(end)
    }
}

struct DayBriefingItem: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var title: String
    var detail: String
    var badge: String?
    var overdue: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, detail, badge, overdue
    }

    init(id: String, title: String, detail: String = "", badge: String? = nil, overdue: Bool = false) {
        self.id = id
        self.title = title
        self.detail = detail
        self.badge = badge
        self.overdue = overdue
    }

    init(from decoder: Decoder) throws {
        let fields = try LenientFields<CodingKeys>(decoder)
        id = fields.content(String.self, .id, fallback: UUID().uuidString)
        title = fields.content(String.self, .title, fallback: "")
        detail = fields.metadata(String.self, .detail, fallback: "")
        badge = fields.metadata(String.self, .badge)
        overdue = fields.metadata(Bool.self, .overdue, fallback: false)
    }
}

struct DayBriefingTravel: Codable, Hashable, Sendable {
    var title: String
    var carMinutes: Int?
    var bikeMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case title, carMinutes, bikeMinutes
    }

    init(title: String, carMinutes: Int? = nil, bikeMinutes: Int? = nil) {
        self.title = title
        self.carMinutes = carMinutes
        self.bikeMinutes = bikeMinutes
    }

    init(from decoder: Decoder) throws {
        let fields = try LenientFields<CodingKeys>(decoder)
        title = fields.content(String.self, .title, fallback: "")
        carMinutes = fields.metadata(Int.self, .carMinutes)
        bikeMinutes = fields.metadata(Int.self, .bikeMinutes)
    }

    var hasTimes: Bool { carMinutes != nil || bikeMinutes != nil }
}

struct DayBriefingRef: Codable, Hashable, Sendable {
    var date: String
    var greetingKey: String
    var weather: WeatherRef?
    var events: [DayBriefingEvent]
    var travel: DayBriefingTravel?
    var reminders: [DayBriefingItem]
    var birthdays: [DayBriefingItem]
    var closing: String

    enum CodingKeys: String, CodingKey {
        case date, greetingKey, weather, events, travel, reminders, birthdays, closing
    }

    init(date: String, greetingKey: String, weather: WeatherRef? = nil, events: [DayBriefingEvent] = [],
         travel: DayBriefingTravel? = nil, reminders: [DayBriefingItem] = [],
         birthdays: [DayBriefingItem] = [], closing: String = "") {
        self.date = date
        self.greetingKey = greetingKey
        self.weather = weather
        self.events = events
        self.travel = travel
        self.reminders = reminders
        self.birthdays = birthdays
        self.closing = closing
    }

    init(from decoder: Decoder) throws {
        let fields = try LenientFields<CodingKeys>(decoder)
        date = fields.content(String.self, .date, fallback: "")
        greetingKey = fields.metadata(String.self, .greetingKey, fallback: "brief_greet_morning")
        weather = fields.content(WeatherRef.self, .weather).flatMap { $0.isOpenable ? $0 : nil }
        events = fields.content([DayBriefingEvent].self, .events, fallback: [])
        travel = fields.content(DayBriefingTravel.self, .travel).flatMap { $0.hasTimes ? $0 : nil }
        reminders = fields.content([DayBriefingItem].self, .reminders, fallback: [])
        birthdays = fields.content([DayBriefingItem].self, .birthdays, fallback: [])
        closing = fields.metadata(String.self, .closing, fallback: "")
    }

    var isUsable: Bool { !date.isEmpty }

    var greeting: String { L.t(greetingKey) }

    var day: Date? { Formatters.eventDay(from: date) }

    var dayText: String {
        guard let day else { return date }
        return Formatters.day(day)
    }

    var selectedDay: BriefingDay? {
        guard let day else { return nil }
        return BriefingDay.between(Date(), and: day)
    }
}
