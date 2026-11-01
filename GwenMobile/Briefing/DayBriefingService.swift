import GwenMobileKit
import Foundation

@MainActor
struct DayBriefingService {
    static let maxEvents = 5
    static let maxReminders = 6
    static let maxBirthdays = 3

    var sources: DayBriefingSources
    var includes: DayBriefingIncludes

    func build(_ day: BriefingDay, now: Date = Date(), system: Calendar = .current) async -> DayBriefingRef {
        let target = system.date(byAdding: .day, value: day.offset, to: now)!
        let start = system.startOfDay(for: target)
        let events = Array(sources.calendar.briefingEvents(on: target).prefix(Self.maxEvents))
        async let weather = weatherRef(day: day)
        async let reminders: [DayBriefingItem] = includes.reminders
            ? (await reminderItems(start: start, system: system)) : []
        async let birthdays: [DayBriefingItem] = includes.birthdays
            ? (await birthdayItems(on: target, system: system)) : []
        async let travel: DayBriefingTravel? = includes.travel
            ? (await travelItem(events: events, now: now)) : nil
        var ref = DayBriefingRef(date: Formatters.stamp(target),
                                 greetingKey: dayGreeting(day),
                                 weather: await weather,
                                 events: events,
                                 travel: await travel,
                                 reminders: await reminders,
                                 birthdays: await birthdays)
        ref.closing = DayBriefingAnswers.closing(ref)
        return ref
    }

    private func weatherRef(day: BriefingDay) async -> WeatherRef? {
        guard includes.weather, let loader = sources.weather else { return nil }
        return try? await loader.briefingWeather(dayOffset: day.offset)
    }

    private func dayGreeting(_ day: BriefingDay) -> String {
        switch day {
        case .today: return "brief_greet_morning"
        case .tomorrow: return "brief_greet_tomorrow"
        case .dayAfter: return "brief_greet_ahead"
        }
    }

    private func reminderItems(start: Date, system: Calendar) async -> [DayBriefingItem] {
        let end = system.date(byAdding: .day, value: 1, to: start)!
        let relevant = await sources.reminders.briefingReminders().filter { reminder in
            guard let due = reminder.due else { return true }
            return due < end
        }
        let sorted = relevant.sorted { left, right in
            let leftRank = rank(left, start: start)
            let rightRank = rank(right, start: start)
            if leftRank != rightRank { return leftRank < rightRank }
            return (left.due ?? .distantFuture) < (right.due ?? .distantFuture)
        }
        return sorted.prefix(Self.maxReminders).map { reminder in
            let overdue = reminder.due.map { $0 < start } ?? false
            var detail = reminder.list
            if let place = reminder.place, !place.isEmpty {
                detail = detail.isEmpty ? place : detail + " · " + place
            }
            return DayBriefingItem(id: reminder.id, title: reminder.title, detail: detail,
                                   badge: badge(reminder, overdue: overdue),
                                   overdue: overdue)
        }
    }

    private func rank(_ reminder: StoredReminder, start: Date) -> Int {
        guard let due = reminder.due else { return 2 }
        return due < start ? 0 : 1
    }

    private func badge(_ reminder: StoredReminder, overdue: Bool) -> String? {
        if overdue { return L.t("brief_overdue") }
        guard let due = reminder.due else { return nil }
        if reminder.allDay { return Formatters.day(due) }
        return Formatters.time(due)
    }

    private func birthdayItems(on day: Date, system: Calendar) async -> [DayBriefingItem] {
        guard let contacts = sources.contacts, await contacts.access() == .granted,
              let cards = try? await contacts.cards() else { return [] }
        let parts = system.dateComponents([.month, .day], from: day)
        let matches = cards.filter { card in
            guard let birthday = card.birthday else { return false }
            return birthday.month == parts.month && birthday.day == parts.day
        }
        return matches.prefix(Self.maxBirthdays).map { card in
            var detail = L.t("brief_birthday")
            if let year = card.birthday?.year,
               let anchor = system.date(from: DateComponents(year: year, month: parts.month, day: parts.day)),
               let years = system.dateComponents([.year], from: anchor, to: day).year,
               (1...120).contains(years) {
                detail = L.fmt("brief_birthday_age", String(years))
            }
            return DayBriefingItem(id: card.id, title: card.name, detail: detail)
        }
    }

    private func travelItem(events: [DayBriefingEvent], now: Date) async -> DayBriefingTravel? {
        guard let travel = sources.travel else { return nil }
        guard let event = events.first(where: { !$0.allDay && $0.start > now && $0.location?.isEmpty == false }),
              let location = event.location else { return nil }
        return await travel.briefingTravel(to: location, departure: event.start.addingTimeInterval(-1800))
    }
}
