@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import CoreLocation
import EventKit
import XCTest
import GwenMobileKit

@MainActor
final class FakeReminderEventStore: ReminderEventStoring {
    var reminders: [EKReminder] = []
    var calendarList: [EKCalendar] = []
    var defaultCalendar: EKCalendar?
    var sourcesList: [EKSource] = []
    var saveFailure: Error?
    var saveCalendarFailure: Error?
    var accessResult = true
    private(set) var saves = 0
    private(set) var removes = 0

    private let backingStore = EKEventStore()
    var makeCalendarOverride: (() -> EKCalendar)?

    func makeReminder() -> EKReminder { EKReminder(eventStore: backingStore) }

    func makeCalendar() -> EKCalendar {
        makeCalendarOverride?() ?? EKCalendar(for: .reminder, eventStore: backingStore)
    }

    func fetchReminders() async -> [EKReminder] { reminders }

    func calendarItem(withIdentifier identifier: String) -> EKCalendarItem? {
        identifier == "unbekannt" ? nil : reminders.first
    }

    func calendars(for entityType: EKEntityType) -> [EKCalendar] { calendarList }

    func defaultCalendarForNewReminders() -> EKCalendar? { defaultCalendar }

    func save(_ reminder: EKReminder, commit: Bool) throws {
        if let saveFailure { throw saveFailure }
        saves += 1
        if !reminders.contains(where: { $0 === reminder }) { reminders.append(reminder) }
    }

    func remove(_ reminder: EKReminder, commit: Bool) throws {
        removes += 1
        reminders.removeAll { $0 === reminder }
    }

    func saveCalendar(_ calendar: EKCalendar, commit: Bool) throws {
        if let saveCalendarFailure { throw saveCalendarFailure }
        calendarList.append(calendar)
    }

    var sources: [EKSource] { sourcesList }

    func requestFullAccessToReminders() async throws -> Bool { accessResult }
}

@MainActor
final class EventKitReminderStoreGapTests: GwenTestCase {
    func testTheStoreCreatesItsDefaultList() throws {
        let fake = FakeReminderEventStore()
        fake.sourcesList = LiveReminderEventStore.shared.sources
        guard !fake.sourcesList.isEmpty else { return }
        fake.makeCalendarOverride = { LiveReminderEventStore.shared.makeCalendar() }
        EventKitReminderStore.storeOverride = fake
        defer { EventKitReminderStore.storeOverride = nil }
        let list = try EventKitReminderStore.makeDefaultList()
        XCTAssertFalse(list.title.isEmpty)
        XCTAssertEqual(fake.calendarList.count, 1)
        _ = EventKitReminderStore.candidateSources()
        fake.saveCalendarFailure = APIError(message: "kaputt")
        XCTAssertThrowsError(try EventKitReminderStore.makeDefaultList())
    }

    func testTheStoreDrivesAFakeBackend() async throws {
        let fake = FakeReminderEventStore()
        EventKitReminderStore.storeOverride = fake
        defer { EventKitReminderStore.storeOverride = nil }
        EventKitReminderStore.accessStatusOverride = .fullAccess
        defer { EventKitReminderStore.accessStatusOverride = nil }

        let store = EventKitReminderStore()
        let fullAccess = await store.hasAccess()
        XCTAssertTrue(fullAccess)
        EventKitReminderStore.accessStatusOverride = .notDetermined
        fake.accessResult = true
        let granted = await store.hasAccess()
        XCTAssertTrue(granted)
        fake.accessResult = false
        let refused = await store.hasAccess()
        XCTAssertFalse(refused)
        EventKitReminderStore.accessStatusOverride = .denied
        let denied = await store.hasAccess()
        XCTAssertFalse(denied)
        EventKitReminderStore.accessStatusOverride = .fullAccess

        let calendar = EKCalendar(for: .reminder, eventStore: EKEventStore())
        calendar.title = "Privat"
        fake.defaultCalendar = calendar
        let title = await store.defaultListTitle()
        XCTAssertEqual(title, "Privat")
        let lists = await store.lists()
        XCTAssertEqual(lists, [])

        var draft = ReminderDraft(title: "Milch", list: "Privat", notes: "Notiz",
                                  due: Date().addingTimeInterval(3600))
        let created = try await store.create(draft)
        XCTAssertEqual(created.title, "Milch")
        XCTAssertGreaterThan(fake.saves, 0)

        draft.title = "Brot"
        _ = try await store.update("egal", with: draft)
        let open = try await store.open()
        XCTAssertFalse(open.isEmpty)
        _ = try await store.complete("egal", at: Date())
        try await store.delete("egal")
        XCTAssertGreaterThan(fake.removes, 0)

        fake.saveFailure = APIError(message: "kaputt")
        do {
            _ = try await store.create(draft)
            XCTFail("erwartet Fehler")
        } catch {}
        fake.saveFailure = nil

        fake.defaultCalendar = nil
        do {
            _ = try await store.create(draft)
        } catch {}
        do {
            _ = try EventKitReminderStore.makeDefaultList()
        } catch {}
        _ = EventKitReminderStore.writableLists()
        _ = EventKitReminderStore.candidateSources()
        XCTAssertFalse(EventKitReminderStore.isLive(""))
        XCTAssertFalse(EventKitReminderStore.isLive("unbekannt"))
    }
}

@MainActor
extension EventKitReminderStoreGapTests {
    func testTheListsSourcesAndFullSnapshot() async throws {
        let fake = FakeReminderEventStore()
        EventKitReminderStore.storeOverride = fake
        EventKitReminderStore.accessStatusOverride = .fullAccess
        defer {
            EventKitReminderStore.storeOverride = nil
            EventKitReminderStore.accessStatusOverride = nil
        }
        fake.calendarList = [EKCalendar(for: .reminder, eventStore: EKEventStore())]
        fake.sourcesList = LiveReminderEventStore.shared.sources
        let store = EventKitReminderStore()
        let lists = await store.lists()
        XCTAssertFalse(lists.isEmpty)
        _ = EventKitReminderStore.candidateSources()
        let due = Date().addingTimeInterval(3600)
        let draft = ReminderDraft(title: "Voll", notes: "Notiz", due: due, allDay: true,
                                  repeatRule: ReminderRepeat(frequency: .weekly, interval: 2),
                                  priority: .high, place: ReminderPlace(name: "Praxis", proximity: .arrive))
        let created = try await store.create(draft)
        XCTAssertEqual(created.title, "Voll")
        XCTAssertEqual(created.priority, .high)
        _ = created.place
        XCTAssertNotNil(created.repeatRule)
    }
}
