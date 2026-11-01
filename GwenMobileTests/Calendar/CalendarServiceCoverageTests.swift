@testable import GwenMobileFeatureCore
import EventKit
import XCTest
import GwenMobileKit

@MainActor
final class CalendarServiceCoverageTests: GwenTestCase {
    private func event(_ title: String, start: Date = Date(),
                       end: Date = Date().addingTimeInterval(1800)) -> EKEvent {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = "Privat"
        event.calendar = calendar
        return event
    }

    func testThePlanProperties() {
        var plan = QwenAPI.CalendarPlan(action: .create)
        plan.title = "Zahnarzt"
        plan.start = "2026-10-05 09:00"
        XCTAssertTrue(plan.needsPlannerPass)
        XCTAssertEqual(plan.lookupWords, "Zahnarzt")
        XCTAssertEqual(plan.givenTitle, "Zahnarzt")
        XCTAssertEqual(plan.eventTitle, "Zahnarzt")
        XCTAssertNotNil(plan.startDate)
        XCTAssertTrue(plan.stepWords.contains("create"))
        plan.action = .update
        plan.find = "Zahnarzt"
        XCTAssertFalse(plan.needsPlannerPass)
        XCTAssertTrue(plan.needsExistingEvent)
        plan.title = nil
        XCTAssertNil(plan.givenTitle)
        XCTAssertEqual(plan.eventTitle, L.t("cal_default_title"))
        plan.action = .delete
        XCTAssertTrue(plan.needsExistingEvent)
        plan.action = .none
        XCTAssertFalse(plan.needsExistingEvent)
    }

    func testUpcomingFiltersSortsAndLimits() {
        let now = Date()
        let items = [(name: "alt", start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(-60)),
                     (name: "später", start: now.addingTimeInterval(7200), end: now.addingTimeInterval(9000)),
                     (name: "gleich", start: now.addingTimeInterval(600), end: now.addingTimeInterval(1200))]
        let upcoming = CalendarService.upcoming(items, now: now, start: { $0.start }, end: { $0.end })
        XCTAssertEqual(upcoming.map(\.name), ["gleich", "später"])
        let limited = CalendarService.upcoming(items, now: now, start: { $0.start }, end: { $0.end },
                                               limit: 1)
        XCTAssertEqual(limited.map(\.name), ["gleich"])
    }

    func testTheAccessPathsWithoutPermission() {
        _ = CalendarService.hasAccess
        _ = CalendarService.accessStatus
        _ = CalendarService.writableCalendarCount
        XCTAssertNil(CalendarService.event(withIdentifier: "x"))
        XCTAssertFalse(CalendarService.isLive("x"))
        XCTAssertNil(CalendarService.event(for: CalendarRef(eventID: "x", title: "t", start: Date())))
        XCTAssertEqual(try? CalendarService.remove(eventID: "x"), false)
        _ = CalendarService.calendarTitles()
        _ = CalendarService.calendarsContext()
        _ = CalendarService.upcomingContext()
        _ = CalendarService.events(on: Date())
        XCTAssertFalse(CalendarService.matches(QwenAPI.CalendarPlan(action: .update, title: "x")))
    }

    func testTheReferenceAndAlertHelpers() {
        let event = event("Zahnarzt")
        event.alarms = [EKAlarm(relativeOffset: -3600), EKAlarm(relativeOffset: -600)]
        XCTAssertEqual(CalendarService.alertMinutes(for: event), [10, 60])
        XCTAssertNotNil(CalendarService.alertSummary(for: event))
        event.alarms = []
        XCTAssertNil(CalendarService.alertSummary(for: event))
        XCTAssertNil(CalendarService.reference(for: event))
        event.alarms = [EKAlarm(absoluteDate: event.startDate.addingTimeInterval(-7200))]
        XCTAssertEqual(CalendarService.alertMinutes(for: event), [120])
    }

    func testTheInternalHelpersCoverTheirBranches() {
        CalendarService.storeOverride = FakeCalendarEventStore()
        defer { CalendarService.storeOverride = nil }
        let event = event("Zahnarzt")
        event.location = "Praxis"
        XCTAssertTrue(CalendarService.describe(event).contains("Praxis"))
        let alarms = CalendarService.alarms(minutesBefore: [0, 5, 10, 100_000])
        XCTAssertEqual(alarms.map(\.relativeOffset), [-300, -600])
        XCTAssertTrue(alarms.allSatisfy { $0.absoluteDate == nil })
        _ = try? CalendarService.targetCalendar(requested: nil, current: nil, silent: .deviceDefault)
        _ = try? CalendarService.targetCalendar(requested: "Fehlt", current: nil, silent: .keepCurrent)
        _ = try? CalendarService.targetCalendar(requested: "Fehlt", current: event.calendar,
                                                silent: .keepCurrent)
        XCTAssertThrowsError(try CalendarService.find("gibt es nicht"))
        XCTAssertThrowsError(try CalendarService.find(nil, requiresTitle: true))
        let searchable = CalendarService.searchableEvents()
        XCTAssertTrue(searchable.events.isEmpty)
        XCTAssertTrue(searchable.candidates.isEmpty)
    }
}
