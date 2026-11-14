@testable import GwenMobileFeatureCore
import EventKit
import XCTest
import GwenMobileKit

@MainActor
final class CalendarServicePerformCoverageTests: GwenTestCase {
    override func tearDown() {
        CalendarService.accessStatusOverride = nil
        super.tearDown()
    }

    private func plan(_ action: QwenAPI.CalendarPlan.Action, title: String? = nil,
                      start: String? = nil) -> QwenAPI.CalendarPlan {
        var plan = QwenAPI.CalendarPlan(action: action)
        plan.title = title
        plan.start = start
        return plan
    }

    func testThePerformPathsThrowWithoutAFullCalendar() async {
        CalendarService.accessStatusOverride = .denied
        do {
            _ = try await CalendarService.perform(plan(.create, title: "Zahnarzt"))
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        CalendarService.accessStatusOverride = .writeOnly
        do {
            _ = try await CalendarService.perform(plan(.create, title: "Zahnarzt"))
            XCTFail("erwartet Fehler")
        } catch {}
    }

    func testThePerformPathsWithSimulatedAccess() async throws {
        CalendarService.accessStatusOverride = .fullAccess
        _ = CalendarService.hasAccess
        do {
            _ = try await CalendarService.perform(plan(.create, title: "Ohne Datum"))
            XCTFail("erwartet Fehler")
        } catch {}
        do {
            _ = try await CalendarService.perform(plan(.create, title: "Zahnarzt",
                                                       start: "2026-10-05 09:00"))
        } catch {}
        do {
            _ = try await CalendarService.perform(plan(.update, title: "Zahnarzt"))
        } catch {}
        do {
            _ = try await CalendarService.perform(plan(.delete, title: "Zahnarzt"))
        } catch {}
        let none = try await CalendarService.perform(plan(.none))
        XCTAssertEqual(none.notice, "")
        XCTAssertNil(none.ref)
    }

    func testTheAccessDependentReaders() async {
        CalendarService.accessStatusOverride = .fullAccess
        _ = CalendarService.calendarTitles()
        _ = CalendarService.calendarsContext()
        _ = CalendarService.upcomingContext()
        _ = CalendarService.events(on: Date())
        _ = CalendarService.writableCalendarCount
        XCTAssertFalse(CalendarService.matches(plan(.update, title: "Nichts")))
        let live = CalendarService.isLive("unbekannt")
        XCTAssertFalse(live)
        _ = try? CalendarService.remove(eventID: "unbekannt")
        CalendarService.accessStatusOverride = .denied
        _ = CalendarService.calendarTitles()
        _ = CalendarService.upcomingContext()
        _ = CalendarService.events(on: Date())
    }

    private func event(_ title: String, start: Date, allDay: Bool = false,
                       location: String? = nil, alarms: [EKAlarm] = []) -> EKEvent {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = start.addingTimeInterval(3600)
        event.isAllDay = allDay
        event.location = location
        event.alarms = alarms
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = "Privat"
        event.calendar = calendar
        return event
    }

    func testTheEventReadersAndContextsWithFakeEvents() async {
        CalendarService.accessStatusOverride = .fullAccess
        let now = Date()
        let todayStart = Calendar.current.startOfDay(for: now)
        let soon = event("Zahnarzt", start: now.addingTimeInterval(-60), location: "Praxis",
                         alarms: [EKAlarm(relativeOffset: -600)])
        let allDay = event("Feiertag", start: todayStart.addingTimeInterval(32 * 3600), allDay: true)
        let past = event("Vorgestern", start: now.addingTimeInterval(-100_000))
        CalendarService.eventsOverride = { from, to in
            [soon, allDay, past].filter { $0.startDate >= from && $0.startDate <= to }
        }
        let context = CalendarService.upcomingContext(now: now)
        XCTAssertTrue(context.contains("Zahnarzt"))
        XCTAssertTrue(context.contains("10 min before"))
        let day = CalendarService.events(on: now)
        XCTAssertEqual(day.first?.title, "Zahnarzt")
        XCTAssertTrue(CalendarService.matches(plan(.update, title: "Zahnarzt")))
        do {
            _ = try await CalendarService.perform(plan(.update, title: "Zahnarzt"))
        } catch {}
        do {
            _ = try await CalendarService.perform(plan(.delete, title: "Zahnarzt"))
        } catch {}
        CalendarService.eventsOverride = nil
        CalendarService.accessStatusOverride = nil
    }
}
