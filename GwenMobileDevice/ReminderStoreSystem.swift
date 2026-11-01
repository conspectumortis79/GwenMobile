@testable import GwenMobileFeatureCore
import GwenMobileKit
import EventKit
import Foundation

private final class ReminderBox: @unchecked Sendable {
    let items: [EKReminder]

    init(items: [EKReminder]) { self.items = items }
}

@MainActor
final class LiveReminderEventStore: ReminderEventStoring {
    static let shared = LiveReminderEventStore()
    private let store = EKEventStore()

    func makeReminder() -> EKReminder { EKReminder(eventStore: store) }

    func makeCalendar() -> EKCalendar { EKCalendar(for: .reminder, eventStore: store) }

    func fetchReminders() async -> [EKReminder] {
        let predicate = store.predicateForReminders(in: nil)
        let box = await withCheckedContinuation { (continuation: CheckedContinuation<ReminderBox, Never>) in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: ReminderBox(items: reminders ?? []))
            }
        }
        return box.items
    }

    func calendarItem(withIdentifier identifier: String) -> EKCalendarItem? {
        store.calendarItem(withIdentifier: identifier)
    }

    func calendars(for entityType: EKEntityType) -> [EKCalendar] { store.calendars(for: entityType) }

    func defaultCalendarForNewReminders() -> EKCalendar? { store.defaultCalendarForNewReminders() }

    func save(_ reminder: EKReminder, commit: Bool) throws { try store.save(reminder, commit: commit) }

    func remove(_ reminder: EKReminder, commit: Bool) throws { try store.remove(reminder, commit: commit) }

    func saveCalendar(_ calendar: EKCalendar, commit: Bool) throws {
        try store.saveCalendar(calendar, commit: commit)
    }

    var sources: [EKSource] { store.sources }

    func requestFullAccessToReminders() async throws -> Bool {
        try await store.requestFullAccessToReminders()
    }
}

@MainActor
enum ReminderStoreSystem {
    static func install() {
        EventKitReminderStore.liveStore = LiveReminderEventStore.shared
    }
}
