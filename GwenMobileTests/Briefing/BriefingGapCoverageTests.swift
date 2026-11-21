@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
private struct GapBriefingCalendar: BriefingCalendarReading {
    var events: [DayBriefingEvent] = []
    func briefingEvents(on day: Date) -> [DayBriefingEvent] { events }
}

@MainActor
private struct GapBriefingReminders: BriefingReminderReading {
    var items: [StoredReminder] = []
    func briefingReminders() async -> [StoredReminder] { items }
}

@MainActor
private struct GapBriefingWeather: BriefingWeatherLoading {
    func briefingWeather(dayOffset: Int) async throws -> WeatherRef {
        throw APIError(message: "kein wetter")
    }
}

@MainActor
private struct GapBriefingTravel: BriefingTravelLooking {
    func briefingTravel(to location: String, departure: Date) async -> DayBriefingTravel? { nil }
}

private struct GapBriefingContacts: ContactDirectory {
    func access() async -> ContactAccess { .denied }
    func cards() async throws -> [ContactCard] { [] }
}

@MainActor
final class BriefingGapCoverageTests: GwenTestCase {
    private func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day,
                                                   hour: hour, minute: minute)) ?? Date()
    }

    private func event(_ title: String, day: Int = 5, hour: Int = 10) -> DayBriefingEvent {
        DayBriefingEvent(id: title, title: title, start: date(day: day, hour: hour),
                         end: date(day: day, hour: hour + 1), allDay: false, location: nil,
                         calendar: "Privat",
                         ref: CalendarRef(eventID: "ev-" + title, title: title,
                                          start: date(day: day, hour: hour)))
    }

    private func reminder(_ title: String, due: Date?, allDay: Bool = false,
                          place: String? = nil, list: String = "Aufgaben") -> StoredReminder {
        StoredReminder(id: title, title: title, list: list, due: due, allDay: allDay, place: place)
    }

    private func sources(events: [DayBriefingEvent] = [], reminders: [StoredReminder] = [])
        -> DayBriefingSources {
        DayBriefingSources(calendar: GapBriefingCalendar(events: events),
                           reminders: GapBriefingReminders(items: reminders),
                           contacts: GapBriefingContacts(),
                           weather: GapBriefingWeather(),
                           travel: GapBriefingTravel())
    }

    func testSmokeTheBriefingDeskCanBeSwappedAndRestored() {
        let desk = DayBriefingDesk()
        desk.stand(in: sources())
        desk.restore()
        desk.restore()
        _ = desk.service(includes: DayBriefingIncludes()).sources.calendar.briefingEvents(on: Date())
    }

    func testTheClosingWordsFollowTheDay() {
        let free = DayBriefingRef(date: "2026-10-05", greetingKey: "brief_greet_morning")
        XCTAssertEqual(DayBriefingAnswers.closing(free), L.t("brief_closing_free"))
        let calm = DayBriefingRef(date: "2026-10-05", greetingKey: "brief_greet_morning",
                                  events: [event("A")])
        XCTAssertEqual(DayBriefingAnswers.closing(calm), L.t("brief_closing_calm"))
        let dense = DayBriefingRef(date: "2026-10-05", greetingKey: "brief_greet_morning",
                                   events: [event("A"), event("B"), event("C")])
        XCTAssertEqual(DayBriefingAnswers.closing(dense), L.n("brief_closing_dense", 3))
        let overdueOne = DayBriefingRef(date: "2026-10-05", greetingKey: "brief_greet_morning",
                                        reminders: [DayBriefingItem(id: "a", title: "A", detail: "",
                                                                    badge: nil, overdue: true)])
        XCTAssertEqual(DayBriefingAnswers.closing(overdueOne), L.t("brief_closing_overdue_one"))
        let overdueTwo = DayBriefingRef(date: "2026-10-05", greetingKey: "brief_greet_morning",
                                        reminders: [DayBriefingItem(id: "a", title: "A", detail: "",
                                                                    badge: nil, overdue: true),
                                                    DayBriefingItem(id: "b", title: "B", detail: "",
                                                                    badge: nil, overdue: true)])
        XCTAssertEqual(DayBriefingAnswers.closing(overdueTwo), L.n("brief_closing_overdue", 2))
    }

    func testTheBriefingTextNamesEventsAndClosings() {
        let empty = DayBriefingRef(date: "2026-10-05", greetingKey: "brief_greet_morning",
                                   closing: DayBriefingAnswers.closing(
                                    DayBriefingRef(date: "2026-10-05", greetingKey: "brief_greet_morning")))
        XCTAssertTrue(DayBriefingAnswers.text(empty).contains(L.t("brief_no_events")))
        let single = DayBriefingRef(date: "2026-10-05", greetingKey: "brief_greet_morning",
                                    events: [event("Zahnarzt")],
                                    reminders: [DayBriefingItem(id: "m", title: "Müll", detail: "",
                                                                badge: nil, overdue: false)],
                                    birthdays: [DayBriefingItem(id: "b", title: "Papa", detail: "63.",
                                                                badge: nil, overdue: false)],
                                    closing: "Ende")
        let text = DayBriefingAnswers.text(single)
        XCTAssertTrue(text.contains(L.t("brief_event_one")), text)
        XCTAssertTrue(text.contains("Müll"), text)
        XCTAssertTrue(text.contains("Papa"), text)
        XCTAssertTrue(text.hasSuffix("Ende"), text)
        let many = DayBriefingRef(date: "2026-10-05", greetingKey: "brief_greet_morning",
                                  events: [event("A"), event("B")])
        XCTAssertTrue(DayBriefingAnswers.text(many).contains(L.n("brief_event_many", 2)))
        XCTAssertFalse(DayBriefingAnswers.notificationBody(single).contains("\n"))
    }

    func testTheBriefingDayHelpersAndDecoding() {
        XCTAssertEqual(BriefingDay.dayAfter.offset, 2)
        XCTAssertEqual(BriefingDay.dayAfter.titleKey, "brief_day_after")
        XCTAssertNotNil(BriefingDay.today.title)
        XCTAssertNil(BriefingDay.between(date(day: 1, hour: 8), and: date(day: 9, hour: 8)))
        XCTAssertEqual(BriefingDay.at(offset: 2), .dayAfter)
        XCTAssertEqual(BriefingDay.at(offset: 9), .tomorrow)
        XCTAssertEqual(DayBriefingRequest().stepWords, "today")
        let eventJSON = #"{"id":"e","title":"T","start":"2026-10-05 10:00","calendar":"C","ref":{"eventID":"","title":"T"}}"#
        let decodedEvent = try? JSONDecoder().decode(DayBriefingEvent.self, from: Data(eventJSON.utf8))
        XCTAssertNil(decodedEvent?.ref)
        let refJSON = #"{"date":"kein datum","weather":{"hours":[]},"travel":{"title":"X"}}"#
        let ref = try? JSONDecoder().decode(DayBriefingRef.self, from: Data(refJSON.utf8))
        XCTAssertNil(ref?.weather)
        XCTAssertNil(ref?.travel)
        XCTAssertNil(ref?.day)
        XCTAssertEqual(ref?.dayText, "kein datum")
        XCTAssertNil(ref?.selectedDay)
    }

    func testTheServiceNamesReminderPlacesAndAllDayBadges() async {
        let service = DayBriefingService(sources: sources(reminders: [
            reminder("Mit Ort", due: date(day: 5, hour: 9), place: "Apotheke"),
            reminder("Ganztags", due: date(day: 5, hour: 0), allDay: true),
            reminder("Ohne Termin", due: nil, place: "Markt"),
        ]), includes: DayBriefingIncludes())
        let ref = await service.build(BriefingDay.today, now: date(day: 5, hour: 8))
        XCTAssertEqual(ref.reminders.count, 3)
        let withPlace = ref.reminders.first { $0.title == "Mit Ort" }
        XCTAssertTrue(withPlace?.detail.contains("Apotheke") ?? false)
        let allDay = ref.reminders.first { $0.title == "Ganztags" }
        XCTAssertEqual(allDay?.badge, Formatters.day(date(day: 5, hour: 0)))
        let noDue = ref.reminders.first { $0.title == "Ohne Termin" }
        XCTAssertNil(noDue?.badge)
        XCTAssertTrue(noDue?.detail.contains("Markt") ?? false)
    }
}
