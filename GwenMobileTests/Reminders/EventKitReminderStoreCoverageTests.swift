@testable import GwenMobileFeatureCore
import EventKit
import XCTest
import GwenMobileKit

@MainActor
final class EventKitReminderStoreCoverageTests: GwenTestCase {
    private func makeReminder() -> EKReminder {
        let store = EKEventStore()
        let reminder = EKReminder(eventStore: store)
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = "Testliste"
        reminder.calendar = calendar
        return reminder
    }

    func testApplyingADraftMapsEveryField() {
        let reminder = makeReminder()
        var draft = ReminderDraft()
        draft.title = "Zahnarzt"
        draft.notes = "Mit Formular"
        draft.due = Date()
        draft.priority = .high
        draft.repeatRule = ReminderRepeat(frequency: .weekly, interval: 2)
        draft.place = ReminderPlace(name: "Praxis", proximity: .leave)
        draft.coordinates = GeoPoint(latitude: 48.1, longitude: 11.5, radius: 120)
        EventKitReminderStore.apply(draft, to: reminder)
        XCTAssertEqual(reminder.title, "Zahnarzt")
        XCTAssertEqual(reminder.notes, "Mit Formular")
        XCTAssertEqual(reminder.priority, 1)
        XCTAssertEqual(reminder.recurrenceRules?.first?.frequency, .weekly)
        XCTAssertEqual(reminder.recurrenceRules?.first?.interval, 2)
        XCTAssertNotNil(reminder.dueDateComponents?.hour)
        XCTAssertEqual(reminder.alarms?.count, 2)
        XCTAssertEqual(reminder.alarms?.first(where: { $0.structuredLocation != nil })?.proximity, .leave)
    }

    func testAnAllDayDraftKeepsOnlyTheDate() {
        var draft = ReminderDraft()
        draft.title = "Ganztags"
        draft.due = Date()
        draft.allDay = true
        draft.priority = .low
        let reminder = makeReminder()
        EventKitReminderStore.apply(draft, to: reminder)
        XCTAssertNil(reminder.dueDateComponents?.hour)
        XCTAssertEqual(reminder.priority, 9)
        EventKitReminderStore.apply(ReminderDraft(), to: reminder)
    }

    func testASnapshotReadsEverythingBack() {
        let reminder = makeReminder()
        reminder.title = "Rechnung"
        reminder.notes = "offen"
        reminder.priority = 9
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 10
        parts.day = 5
        parts.hour = 9
        reminder.dueDateComponents = parts
        reminder.recurrenceRules = [EKRecurrenceRule(recurrenceWith: .monthly, interval: 3, end: nil)]
        let alarm = EKAlarm()
        alarm.structuredLocation = EKStructuredLocation(title: "Büro")
        alarm.proximity = .enter
        reminder.alarms = [alarm]
        let stored = EventKitReminderStore.snapshot(reminder)
        XCTAssertEqual(stored.title, "Rechnung")
        XCTAssertEqual(stored.list, "Testliste")
        XCTAssertEqual(stored.notes, "offen")
        XCTAssertEqual(stored.priority, .low)
        XCTAssertEqual(stored.place, "Büro")
        XCTAssertEqual(stored.proximity, .arrive)
        XCTAssertEqual(stored.repeatRule, ReminderRepeat(frequency: .monthly, interval: 3))
        XCTAssertNotNil(stored.due)
        XCTAssertFalse(stored.allDay)
        XCTAssertFalse(stored.isCompleted)
    }

    func testTheMappingHelpersCoverEveryCase() {
        XCTAssertNil(EventKitReminderStore.priority(0))
        XCTAssertEqual(EventKitReminderStore.priority(1), .high)
        XCTAssertEqual(EventKitReminderStore.priority(4), .high)
        XCTAssertNil(EventKitReminderStore.priority(5))
        XCTAssertEqual(EventKitReminderStore.priority(9), .low)
        let cases: [(EKRecurrenceFrequency, ReminderRepeat.Frequency)] = [
            (.daily, .daily), (.weekly, .weekly), (.monthly, .monthly), (.yearly, .yearly)
        ]
        for (ekFrequency, frequency) in cases {
            let rule = EKRecurrenceRule(recurrenceWith: ekFrequency, interval: 1, end: nil)
            XCTAssertEqual(EventKitReminderStore.repeatRule(rule)?.frequency, frequency)
            XCTAssertEqual(EventKitReminderStore.frequency(frequency), ekFrequency)
        }
        XCTAssertNotNil(EventKitReminderStore.dueAlarm())
        XCTAssertEqual(EventKitReminderStore.recurrence(ReminderRepeat(frequency: .daily)).frequency, .daily)
    }

    func testTheAccessAndListingPaths() async {
        XCTAssertFalse(EventKitReminderStore.isLive(""))
        XCTAssertFalse(EventKitReminderStore.isLive("unbekannt"))
        _ = EventKitReminderStore.hasAccess
        _ = EventKitReminderStore.accessStatus
        let store = EventKitReminderStore()
        _ = await store.lists()
        _ = await store.defaultListTitle()
        _ = try? await store.open()
        _ = await EventKitReminderStore.snapshots()
        _ = EventKitReminderStore.candidateSources()
        _ = EventKitReminderStore.writableLists()
        _ = try? EventKitReminderStore.calendar(named: nil)
        _ = try? EventKitReminderStore.calendar(named: "Gibt es nicht")
        _ = try? EventKitReminderStore.makeDefaultList()
    }

    func testTheWritePathsReportAnUnknownReminder() async {
        let store = EventKitReminderStore()
        var draft = ReminderDraft()
        draft.title = "Neu"
        XCTAssertThrowsError(try EventKitReminderStore.live("fehlt"))
        do {
            _ = try await store.update("fehlt", with: draft)
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        do {
            _ = try await store.complete("fehlt", at: Date())
            XCTFail("erwartet Fehler")
        } catch {}
        do {
            try await store.delete("fehlt")
            XCTFail("erwartet Fehler")
        } catch {}
        _ = try? await store.create(draft)
    }

    func testTheStorePathsWithSimulatedFullAccess() async {
        EventKitReminderStore.accessStatusOverride = .fullAccess
        defer { EventKitReminderStore.accessStatusOverride = nil }
        let store = EventKitReminderStore()
        let granted = await store.hasAccess()
        XCTAssertTrue(granted)
        XCTAssertTrue(EventKitReminderStore.hasAccess)
        _ = EventKitReminderStore.isLive("unbekannt")
        _ = await store.lists()
        _ = await store.defaultListTitle()
        let open = try? await store.open()
        XCTAssertNotNil(open)
        var draft = ReminderDraft()
        draft.title = "Neu"
        _ = try? await store.create(draft)
        _ = try? EventKitReminderStore.makeDefaultList()
        _ = try? EventKitReminderStore.calendar(named: "Fehlt")
        EventKitReminderStore.accessStatusOverride = .denied
        let denied = await store.hasAccess()
        XCTAssertFalse(denied)
    }
}
