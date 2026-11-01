@testable import GwenMobileFeatureCore
import EventKit
import XCTest
import GwenMobileKit

@MainActor
final class FakeCalendarEventStore: CalendarEventStoring {
    var calendarsList: [EKCalendar] = []
    var defaultCalendar: EKCalendar?
    var defaultEvents: [EKEvent] = []
    var eventsByID: [String: EKEvent] = [:]
    var savedEvents: [EKEvent] = []
    var removedEvents: [EKEvent] = []
    var accessResult = true
    var saveFailure: Error?

    let eventStore = EKEventStore()

    func makeEvent() -> EKEvent { EKEvent(eventStore: eventStore) }

    func events(matching predicate: NSPredicate) -> [EKEvent] { defaultEvents }

    func predicateForEvents(withStart start: Date, end: Date, calendars: [EKCalendar]?) -> NSPredicate {
        NSPredicate(value: true)
    }

    func event(withIdentifier identifier: String) -> EKEvent? {
        eventsByID[identifier] ?? defaultEvents.first { $0.eventIdentifier == identifier }
    }

    func remove(_ event: EKEvent, span: EKSpan) throws {
        removedEvents.append(event)
    }

    func save(_ event: EKEvent, span: EKSpan) throws {
        if let saveFailure { throw saveFailure }
        savedEvents.append(event)
    }

    func requestFullAccessToEvents() async throws -> Bool { accessResult }

    func calendars(for entityType: EKEntityType) -> [EKCalendar] { calendarsList }

    var defaultCalendarForNewEvents: EKCalendar? { defaultCalendar }
}

@MainActor
final class CalendarServiceGapTests: GwenTestCase {
    private func calendar(_ title: String) -> EKCalendar {
        let calendar = EKCalendar(for: .event, eventStore: EKEventStore())
        calendar.title = title
        return calendar
    }

    func testTheCalendarServiceRunsOnAFakeStore() async throws {
        let fake = FakeCalendarEventStore()
        CalendarService.storeOverride = fake
        CalendarService.accessStatusOverride = .fullAccess
        defer {
            CalendarService.storeOverride = nil
            CalendarService.accessStatusOverride = nil
            CalendarService.eventsOverride = nil
        }
        let privat = calendar("Privat")
        fake.calendarsList = [privat]
        fake.defaultCalendar = privat

        var plan = QwenAPI.CalendarPlan(action: .create)
        plan.title = "Zahnarzt"
        plan.start = "2026-10-05 09:00"
        plan.end = "2026-10-05 10:00"
        plan.location = "Praxis"
        plan.notes = "Kontrolle"
        plan.alerts = [15, 0, 999_999]
        plan.calendar = "Privat"
        let created = try await CalendarService.perform(plan)
        XCTAssertFalse(created.notice.isEmpty)
        XCTAssertFalse(fake.savedEvents.isEmpty)

        var reversed = QwenAPI.CalendarPlan(action: .create)
        reversed.title = "Rückwärts"
        reversed.start = "2026-10-05 10:00"
        reversed.end = "2026-10-05 09:00"
        reversed.calendar = "Privat"
        _ = try await CalendarService.perform(reversed)
        let backwards = try XCTUnwrap(fake.savedEvents.last)
        XCTAssertEqual(backwards.endDate.timeIntervalSince(backwards.startDate), 30 * 60)

        let event = EKEvent(eventStore: fake.eventStore)
        event.title = "Zahnarzt"
        event.startDate = Date()
        event.endDate = Date().addingTimeInterval(1800)
        event.calendar = privat
        CalendarService.eventsOverride = { _, _ in [event] }
        var update = QwenAPI.CalendarPlan(action: .update)
        update.title = "Zahnarzt"
        update.start = "2026-10-06 09:00"
        update.notes = "neu"
        update.calendar = "Privat"
        update.alerts = [10]
        _ = try await CalendarService.perform(update)
        update.start = nil
        update.alerts = nil
        update.end = "2026-10-06 10:30"
        _ = try await CalendarService.perform(update)
        XCTAssertEqual(event.endDate, Formatters.eventDate(from: "2026-10-06 10:30"))
        var delete = QwenAPI.CalendarPlan(action: .delete)
        delete.title = "Zahnarzt"
        _ = try await CalendarService.perform(delete)
        XCTAssertFalse(fake.removedEvents.isEmpty)
        let none = try await CalendarService.perform(QwenAPI.CalendarPlan(action: .none))
        XCTAssertEqual(none.notice, "")

        var noDate = QwenAPI.CalendarPlan(action: .create)
        noDate.title = "Ohne Datum"
        do {
            _ = try await CalendarService.perform(noDate)
            XCTFail("erwartet Fehler")
        } catch {}

        CalendarService.accessStatusOverride = .notDetermined
        fake.accessResult = true
        let access = await CalendarService.ensureAccess()
        XCTAssertTrue(access)
        fake.accessResult = false
        let refused = await CalendarService.ensureAccess()
        XCTAssertFalse(refused)
        CalendarService.accessStatusOverride = .denied
        let denied = await CalendarService.ensureAccess()
        XCTAssertFalse(denied)

        CalendarService.accessStatusOverride = .fullAccess
        let alarmEvent = EKEvent(eventStore: fake.eventStore)
        alarmEvent.title = "Alarmtermin"
        alarmEvent.startDate = Date().addingTimeInterval(3600)
        alarmEvent.endDate = Date().addingTimeInterval(5400)
        alarmEvent.calendar = privat
        alarmEvent.alarms = [EKAlarm(relativeOffset: -600)]
        fake.eventsByID["alarm"] = alarmEvent
        CalendarService.eventsOverride = { _, _ in [alarmEvent] }
        var move = QwenAPI.CalendarPlan(action: .update)
        move.title = "Alarmtermin"
        move.start = "2026-10-09 09:00"
        move.alerts = nil
        _ = try await CalendarService.perform(move)
        XCTAssertNotNil(alarmEvent.alarms)
        XCTAssertTrue(try CalendarService.remove(eventID: "alarm"))
        CalendarService.eventsOverride = nil

        _ = CalendarService.matches(update)
        _ = try? CalendarService.find("Zahnarzt")
        _ = CalendarService.reference(for: event)
        _ = CalendarService.calendarTitles()
        _ = CalendarService.writableCalendarCount
        _ = try? CalendarService.remove(eventID: "unbekannt")
        _ = CalendarService.alarms(minutesBefore: [5, 0, 999_999, -1])
        _ = CalendarService.alertMinutes(for: event)
        _ = CalendarService.alertSummary(for: event)
        _ = CalendarService.describe(event)

        do {
            _ = try CalendarService.targetCalendar(requested: "Gibt es nicht", current: nil,
                                                   silent: .deviceDefault)
            XCTFail("erwartet Fehler")
        } catch {}
        do {
            _ = try CalendarService.targetCalendar(requested: nil, current: nil, silent: .keepCurrent)
            XCTFail("erwartet Fehler")
        } catch {}
        do {
            _ = try await CalendarService.perform(update)
        } catch {}
    }
}

@MainActor
extension CalendarServiceGapTests {
    func testTheCalendarHelpersKeepTheCurrentAndSortEvents() throws {
        let (fake, calendar) = fakeCalendar()
        let kept = try CalendarService.targetCalendar(requested: nil, current: calendar, silent: .keepCurrent)
        XCTAssertEqual(kept.title, "Privat")
        let first = EKEvent(eventStore: fake.eventStore)
        first.title = "A"
        first.startDate = Date()
        first.endDate = Date().addingTimeInterval(600)
        first.isAllDay = false
        first.calendar = calendar
        let second = EKEvent(eventStore: fake.eventStore)
        second.title = "B"
        second.startDate = first.startDate
        second.endDate = first.endDate
        second.isAllDay = true
        second.calendar = calendar
        CalendarService.eventsOverride = { _, _ in [second, first] }
        let events = CalendarService.events(on: first.startDate)
        XCTAssertEqual(events.map(\.title), ["A", "B"])
    }
}

@MainActor
extension CalendarServiceGapTests {
    func testTheCalendarContextAndEventHelpers() throws {
        let (fake, calendar) = fakeCalendar()
        let event = EKEvent(eventStore: fake.eventStore)
        event.title = "Termin"
        event.startDate = Date()
        event.endDate = Date().addingTimeInterval(1800)
        event.calendar = calendar
        event.location = "Praxis"
        event.notes = "Notiz"
        event.alarms = [EKAlarm(relativeOffset: -600)]
        fake.defaultEvents = [event]
        _ = CalendarService.upcomingContext()
        _ = CalendarService.calendarsContext()
        _ = CalendarService.events(on: Date())
        _ = CalendarService.searchableEvents()
        _ = CalendarService.reference(for: event)
        _ = CalendarService.alertMinutes(for: event)
        _ = CalendarService.describe(event)
        _ = CalendarService.alertSummary(for: event)
        var plan = QwenAPI.CalendarPlan(action: .create)
        plan.title = "Termin"
        plan.find = "Termin"
        XCTAssertFalse(plan.lookupWords.isEmpty)
        _ = CalendarService.matches(plan)
    }

    func testTheCalendarEventsSortTimedEntriesByStart() {
        let (fake, calendar) = fakeCalendar()
        let later = EKEvent(eventStore: fake.eventStore)
        later.title = "Spät"
        later.startDate = Date().addingTimeInterval(3_600)
        later.endDate = later.startDate.addingTimeInterval(600)
        later.isAllDay = false
        later.calendar = calendar
        let earlier = EKEvent(eventStore: fake.eventStore)
        earlier.title = "Früh"
        earlier.startDate = Date()
        earlier.endDate = earlier.startDate.addingTimeInterval(600)
        earlier.isAllDay = false
        earlier.calendar = calendar
        CalendarService.eventsOverride = { _, _ in [later, earlier] }
        XCTAssertEqual(CalendarService.events(on: Date()).map(\.title), ["Früh", "Spät"])
    }

    func testAReferenceNeedsAnIdentifier() {
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertNil(CalendarService.reference(id: nil, title: "Zahnarzt", start: start))
        XCTAssertNil(CalendarService.reference(id: "", title: "Zahnarzt", start: start))
        let ref = CalendarService.reference(id: "ID-1", title: "Zahnarzt", start: start)
        XCTAssertEqual(ref?.eventID, "ID-1")
        XCTAssertEqual(ref?.title, "Zahnarzt")
        XCTAssertEqual(ref?.start, start)
        XCTAssertEqual(CalendarService.reference(id: "ID-1", title: nil, start: start)?.title, "")
    }

    func testAnOutcomeWithAnUnknownTitleIsRefused() throws {
        let store = EKEventStore()
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = "Privat"
        XCTAssertEqual(try CalendarService.calendar(named: "Privat", in: [calendar], titles: ["Privat"]).title,
                       "Privat")
        XCTAssertThrowsError(try CalendarService.calendar(named: "Fehlt", in: [calendar], titles: ["Privat"]))
    }
}
