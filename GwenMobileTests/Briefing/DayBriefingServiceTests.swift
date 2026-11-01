@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
private struct BriefingCalendarStub: BriefingCalendarReading {
    var events: [DayBriefingEvent]

    func briefingEvents(on day: Date) -> [DayBriefingEvent] {
        events.filter { Calendar.current.isDate($0.start, inSameDayAs: day) }
    }
}

@MainActor
private struct BriefingReminderStub: BriefingReminderReading {
    var items: [StoredReminder]

    func briefingReminders() async -> [StoredReminder] { items }
}

@MainActor
private struct BriefingWeatherStub: BriefingWeatherLoading {
    var ref: WeatherRef?
    var failure: Error?

    func briefingWeather(dayOffset: Int) async throws -> WeatherRef {
        if let failure { throw failure }
        guard let ref else { throw APIError(message: "kein Wetter") }
        return ref
    }
}

@MainActor
private struct BriefingTravelStub: BriefingTravelLooking {
    var trip: DayBriefingTravel?

    func briefingTravel(to location: String, departure: Date) async -> DayBriefingTravel? { trip }
}

private struct BriefingContactStub: ContactDirectory {
    var cards: [ContactCard]

    func access() async -> ContactAccess { .granted }

    func cards() async throws -> [ContactCard] { cards }
}

@MainActor
final class DayBriefingServiceTests: GwenTestCase {
    private let base = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5,
                                                                 hour: 8, minute: 0)) ?? Date()

    private func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day,
                                                   hour: hour, minute: minute)) ?? base
    }

    private func event(_ title: String, day: Int, hour: Int, endHour: Int? = nil,
                       location: String? = nil, allDay: Bool = false) -> DayBriefingEvent {
        DayBriefingEvent(id: title, title: title, start: date(day: day, hour: hour),
                         end: endHour.map { date(day: day, hour: $0) },
                         allDay: allDay, location: location, calendar: "Privat",
                         ref: CalendarRef(eventID: "ev-" + title, title: title,
                                          start: date(day: day, hour: hour)))
    }

    private func reminder(_ title: String, due: Date?, list: String = "Aufgaben",
                          allDay: Bool = false) -> StoredReminder {
        StoredReminder(id: title, title: title, list: list, due: due, allDay: allDay)
    }

    private func weather() -> WeatherRef {
        WeatherFixture.ref(hours: WeatherFixture.day { hour in
            WeatherFixture.hour(hour, temp: hour < 12 ? 9 : 14, rain: hour < 12 ? 70 : 0,
                                precip: hour < 12 ? 1.2 : 0, kind: hour < 12 ? .rain : .partly)
        })
    }

    private func service(includes: DayBriefingIncludes = DayBriefingIncludes(),
                         weatherRef: WeatherRef? = nil, weatherFailure: Error? = nil,
                         trip: DayBriefingTravel? = DayBriefingTravel(title: "Praxis am Ring 12",
                                                                      carMinutes: 18, bikeMinutes: 25))
        -> DayBriefingService {
        let sources = DayBriefingSources(
            calendar: BriefingCalendarStub(events: [
                event("Zahnarzt Dr. Berger", day: 5, hour: 11, endHour: 12, location: "Praxis am Ring 12"),
                event("Team-Call", day: 5, hour: 15, endHour: 16),
                event("Elternabend", day: 5, hour: 18, endHour: 20),
                event("Physio", day: 6, hour: 8, endHour: 10)
            ]),
            reminders: BriefingReminderStub(items: [
                reminder("Stadtwerke-Rechnung", due: date(day: 4, hour: 9)),
                reminder("Einkaufsliste", due: nil),
                reminder("Müll rausstellen", due: date(day: 5, hour: 19)),
                reminder("Nächste Woche", due: date(day: 9, hour: 9))
            ]),
            contacts: BriefingContactStub(cards: [
                ContactCard(id: "papa", name: "Papa", nameParts: ["Papa"],
                            birthday: DateComponents(year: 1963, month: 10, day: 5)),
                ContactCard(id: "anna", name: "Anna", nameParts: ["Anna"],
                            birthday: DateComponents(month: 10, day: 6)),
                ContactCard(id: "ohne", name: "Ohne Datum", nameParts: ["Ohne"])
            ]),
            weather: BriefingWeatherStub(ref: weatherRef ?? weather(), failure: weatherFailure),
            travel: BriefingTravelStub(trip: trip)
        )
        return DayBriefingService(sources: sources, includes: includes)
    }

    func testTheBriefingBringsTheWholeDayTogether() async {
        let ref = await service().build(.today, now: base)
        XCTAssertEqual(ref.date, "2026-10-05")
        XCTAssertEqual(ref.greetingKey, "brief_greet_morning")
        XCTAssertEqual(ref.events.count, 3)
        XCTAssertEqual(ref.events.first?.title, "Zahnarzt Dr. Berger")
        XCTAssertEqual(ref.reminders.count, 3)
        XCTAssertEqual(ref.reminders.first?.title, "Stadtwerke-Rechnung")
        XCTAssertEqual(ref.reminders.first?.overdue, true)
        XCTAssertEqual(ref.reminders.first?.badge, L.t("brief_overdue"))
        XCTAssertEqual(ref.birthdays.map(\.title), ["Papa"])
        XCTAssertEqual(ref.birthdays.first?.detail, "turns 63")
        XCTAssertEqual(ref.travel?.title, "Praxis am Ring 12")
        XCTAssertEqual(ref.travel?.carMinutes, 18)
        XCTAssertEqual(ref.weather?.hours.count, 17)
        XCTAssertEqual(ref.closing, L.t("brief_closing_overdue_one"))
    }

    func testTheWeatherLineCarriesTheRangeAndTheAdvice() async {
        let ref = await service().build(.today, now: base)
        let line = try? XCTUnwrap(ref.weather.flatMap { DayBriefingAnswers.weatherLine($0) })
        XCTAssertEqual(line?.contains("9–14 °C"), true, line ?? "")
        XCTAssertEqual(line?.contains("Umbrella"), true, line ?? "")
    }

    func testTheTextNamesTheFirstEventTheWeatherAndTheOpenThings() async {
        let ref = await service().build(.today, now: base)
        let text = DayBriefingAnswers.text(ref)
        XCTAssertTrue(text.hasPrefix("Good morning."), text)
        XCTAssertTrue(text.contains("3 appointments"), text)
        XCTAssertTrue(text.contains("Zahnarzt Dr. Berger"), text)
        XCTAssertTrue(text.contains("Open: Stadtwerke-Rechnung, Müll rausstellen, Einkaufsliste"), text)
        XCTAssertTrue(text.contains("Papa"), text)
        XCTAssertTrue(text.contains("9–14 °C"), text)
    }

    func testTomorrowKeepsItsOwnDateAndGreeting() async {
        let ref = await service().build(.tomorrow, now: base)
        XCTAssertEqual(ref.date, "2026-10-06")
        XCTAssertEqual(ref.greetingKey, "brief_greet_tomorrow")
        XCTAssertEqual(ref.events.map(\.title), ["Physio"])
        XCTAssertEqual(ref.birthdays.map(\.title), ["Anna"])
        XCTAssertEqual(ref.birthdays.first?.detail, "has a birthday")
        XCTAssertNil(ref.travel)
    }

    func testTheDayAfterTomorrowGetsItsOwnGreeting() async {
        let ref = await service().build(.dayAfter, now: base)
        XCTAssertEqual(ref.date, "2026-10-07")
        XCTAssertEqual(ref.greetingKey, "brief_greet_ahead")
        XCTAssertTrue(ref.events.isEmpty)
    }

    func testTheOpenRemindersSkipFarAwayDatesAndWaitForTheirOrder() async {
        let ref = await service().build(.today, now: base)
        XCTAssertEqual(ref.reminders.map(\.title), ["Stadtwerke-Rechnung", "Müll rausstellen", "Einkaufsliste"])
        XCTAssertEqual(ref.reminders.last?.badge, nil)
        XCTAssertEqual(ref.reminders[1].badge, Formatters.time(date(day: 5, hour: 19)))
    }

    func testTheIncludesTurnSingleSectionsOff() async {
        let ref = await service(includes: DayBriefingIncludes(weather: false, reminders: false,
                                                              birthdays: false, travel: false))
            .build(.today, now: base)
        XCTAssertNil(ref.weather)
        XCTAssertNil(ref.travel)
        XCTAssertTrue(ref.reminders.isEmpty)
        XCTAssertTrue(ref.birthdays.isEmpty)
        XCTAssertEqual(ref.events.count, 3)
    }

    func testAFailingForecastIsLeftOutInsteadOfGuessed() async {
        let ref = await service(weatherFailure: APIError(message: "HTTP 503")).build(.today, now: base)
        XCTAssertNil(ref.weather)
        XCTAssertFalse(DayBriefingAnswers.text(ref).contains("°C"))
    }

    func testTheTravelTimeBelongsToTheNextEventWithAPlace() async {
        let ref = await service().build(.today, now: base)
        let text = ref.travel.map(DayBriefingAnswers.travelText) ?? ""
        XCTAssertEqual(text, "18 min by car · 25 min by bike")
    }

    func testWithoutATripNoTravelSectionAppears() async {
        let ref = await service(trip: nil).build(.today, now: base)
        XCTAssertNil(ref.travel)
    }

    func testTheEventLimitKeepsTheCardShort() async {
        let events = (0..<8).map { event("Termin \($0)", day: 5, hour: min(8 + $0, 23)) }
        let sources = DayBriefingSources(calendar: BriefingCalendarStub(events: events),
                                         reminders: BriefingReminderStub(items: []),
                                         contacts: nil, weather: nil, travel: nil)
        let ref = await DayBriefingService(sources: sources, includes: DayBriefingIncludes())
            .build(.today, now: base)
        XCTAssertEqual(ref.events.count, DayBriefingService.maxEvents)
    }

    func testTheBirthdayAgeOnlyCountsRealYears() async {
        let sources = DayBriefingSources(
            calendar: BriefingCalendarStub(events: []),
            reminders: BriefingReminderStub(items: []),
            contacts: BriefingContactStub(cards: [
                ContactCard(id: "alt", name: "Oma", nameParts: ["Oma"],
                            birthday: DateComponents(year: 1900, month: 10, day: 5))
            ]),
            weather: nil, travel: nil)
        let ref = await DayBriefingService(sources: sources, includes: DayBriefingIncludes())
            .build(.today, now: base)
        XCTAssertEqual(ref.birthdays.first?.detail, "has a birthday")
    }

    func testBetweenMapsAStoredDateBackToItsTab() {
        XCTAssertEqual(BriefingDay.between(base, and: date(day: 5, hour: 20)), .today)
        XCTAssertEqual(BriefingDay.between(base, and: date(day: 6, hour: 8)), .tomorrow)
        XCTAssertEqual(BriefingDay.between(base, and: date(day: 7, hour: 8)), .dayAfter)
        XCTAssertNil(BriefingDay.between(base, and: date(day: 9, hour: 8)))
    }

    func testTheBriefingTravelsWithTheMessage() async throws {
        let ref = await service().build(.today, now: base)
        let message = ChatMessage(role: .assistant, text: "Guten Morgen.", dayBriefingRef: ref)
        let data = try JSONEncoder().encode(message)
        let back = try JSONDecoder().decode(ChatMessage.self, from: data)
        XCTAssertEqual(back.dayBriefingRef?.date, ref.date)
        XCTAssertEqual(back.dayBriefingRef?.events.first?.title, "Zahnarzt Dr. Berger")
        XCTAssertEqual(back.dayBriefingRef?.reminders.count, 3)
    }

    func testTheNotificationBodyIsOneLineOfTheBriefingText() async {
        let ref = await service().build(.today, now: base)
        let body = DayBriefingAnswers.notificationBody(ref)
        XCTAssertFalse(body.contains("\n"))
        XCTAssertTrue(body.contains("Zahnarzt Dr. Berger"), body)
        XCTAssertEqual(DayBriefingAnswers.notificationTitle(), L.t("brief_notify_title"))
    }
}
