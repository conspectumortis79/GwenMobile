import GwenMobileKit
import CoreLocation
import EventKit
import Foundation

@MainActor
protocol ReminderEventStoring {
    func makeReminder() -> EKReminder
    func makeCalendar() -> EKCalendar
    func fetchReminders() async -> [EKReminder]
    func calendarItem(withIdentifier identifier: String) -> EKCalendarItem?
    func calendars(for entityType: EKEntityType) -> [EKCalendar]
    func defaultCalendarForNewReminders() -> EKCalendar?
    func save(_ reminder: EKReminder, commit: Bool) throws
    func remove(_ reminder: EKReminder, commit: Bool) throws
    func saveCalendar(_ calendar: EKCalendar, commit: Bool) throws
    var sources: [EKSource] { get }
    func requestFullAccessToReminders() async throws -> Bool
}

@MainActor
final class StubReminderEventStore: ReminderEventStoring {
    private let store = EKEventStore()

    func makeReminder() -> EKReminder { EKReminder(eventStore: store) }
    func makeCalendar() -> EKCalendar { EKCalendar(for: .reminder, eventStore: store) }
    func fetchReminders() async -> [EKReminder] { [] }
    func calendarItem(withIdentifier identifier: String) -> EKCalendarItem? { nil }
    func calendars(for entityType: EKEntityType) -> [EKCalendar] { [] }
    func defaultCalendarForNewReminders() -> EKCalendar? { nil }
    func save(_ reminder: EKReminder, commit: Bool) throws {}
    func remove(_ reminder: EKReminder, commit: Bool) throws {}
    func saveCalendar(_ calendar: EKCalendar, commit: Bool) throws {}
    var sources: [EKSource] { [] }
    func requestFullAccessToReminders() async throws -> Bool { false }
}

@MainActor
struct EventKitReminderStore: ReminderStoring {
    nonisolated(unsafe) static var storeOverride: (any ReminderEventStoring)?

    nonisolated(unsafe) static var liveStore: (any ReminderEventStoring)?

    static var store: any ReminderEventStoring { storeOverride ?? liveStore ?? StubReminderEventStore() }

    static var accessStatus: EKAuthorizationStatus { accessStatusOverride ?? EKEventStore.authorizationStatus(for: .reminder) }

    nonisolated(unsafe) static var accessStatusOverride: EKAuthorizationStatus?

    static var hasAccess: Bool { accessStatus == .fullAccess }

    static func isLive(_ id: String) -> Bool {
        guard hasAccess, !id.isEmpty else { return false }
        return store.calendarItem(withIdentifier: id) != nil
    }

    func hasAccess() async -> Bool {
        switch Self.accessStatus {
        case .fullAccess:
            return true
        case .notDetermined:
            return ((try? await Self.store.requestFullAccessToReminders()) ?? false)
        default:
            return false
        }
    }

    func lists() async -> [String] {
        Self.writableLists().map(\.title)
    }

    func defaultListTitle() async -> String? {
        Self.store.defaultCalendarForNewReminders()?.title
    }

    func open() async throws -> [StoredReminder] {
        let all = await Self.snapshots()
        return all.filter { !$0.isCompleted }
    }

    func create(_ draft: ReminderDraft) async throws -> StoredReminder {
        let reminder = Self.store.makeReminder()
        reminder.calendar = try Self.calendar(named: draft.list)
        Self.apply(draft, to: reminder)
        try Self.store.save(reminder, commit: true)
        return Self.snapshot(reminder)
    }

    func update(_ id: String, with draft: ReminderDraft) async throws -> StoredReminder {
        let reminder = try Self.live(id)
        if let list = draft.list {
            reminder.calendar = try Self.calendar(named: list)
        }
        Self.apply(draft, to: reminder)
        try Self.store.save(reminder, commit: true)
        return Self.snapshot(reminder)
    }

    func complete(_ id: String, at date: Date) async throws -> StoredReminder {
        let reminder = try Self.live(id)
        reminder.isCompleted = true
        reminder.completionDate = date
        try Self.store.save(reminder, commit: true)
        return Self.snapshot(reminder)
    }

    func delete(_ id: String) async throws {
        let reminder = try Self.live(id)
        try Self.store.remove(reminder, commit: true)
    }

    static func live(_ id: String) throws -> EKReminder {
        guard let item = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw APIError(message: L.t("rem_gone"))
        }
        return item
    }

    static func writableLists() -> [EKCalendar] {
        store.calendars(for: .reminder).filter { $0.allowsContentModifications }
    }

    static func calendar(named title: String?) throws -> EKCalendar {
        if let title, let hit = writableLists().first(where: { $0.title == title }) {
            return hit
        }
        if let fallback = store.defaultCalendarForNewReminders() {
            return fallback
        }
        if let first = writableLists().first {
            return first
        }
        return try makeDefaultList()
    }

    static func makeDefaultList() throws -> EKCalendar {
        let title = L.t("rem_default_list")
        var lastError: Error?
        for source in candidateSources() {
            let calendar = store.makeCalendar()
            calendar.title = title
            calendar.source = source
            do {
                try store.saveCalendar(calendar, commit: true)
                flowMark("ERINNERUNG liste angelegt titel=\(title) quelle=\(source.title)")
                return calendar
            } catch {
                lastError = error
            }
        }
        throw APIError(message: L.t("rem_no_list")
            + (lastError.map { " " + $0.localizedDescription } ?? ""))
    }

    static func candidateSources() -> [EKSource] {
        store.sources.filter { $0.sourceType != .subscribed && $0.sourceType != .birthdays }
    }

    static func apply(_ draft: ReminderDraft, to reminder: EKReminder) {
        if let title = draft.title, !title.isEmpty {
            reminder.title = title
        }
        if let notes = draft.notes {
            reminder.notes = notes
        }
        if let rule = draft.repeatRule {
            reminder.recurrenceRules = [recurrence(rule)]
        }
        if let priority = draft.priority {
            reminder.priority = priority.ekPriority
        }
        if let due = draft.due {
            var parts = Calendar.current.dateComponents([.year, .month, .day], from: due)
            if !draft.allDay {
                let time = Calendar.current.dateComponents([.hour, .minute], from: due)
                parts.hour = time.hour
                parts.minute = time.minute
            }
            reminder.dueDateComponents = parts
        }
        var alarms = reminder.alarms ?? []
        if draft.due != nil {
            alarms.removeAll { $0.structuredLocation == nil }
            alarms.append(Self.dueAlarm())
        }
        if let place = draft.place, let point = draft.coordinates {
            alarms.removeAll { $0.structuredLocation != nil }
            let location = EKStructuredLocation(title: place.name)
            location.geoLocation = CLLocation(latitude: point.latitude, longitude: point.longitude)
            location.radius = point.radius
            let alarm = EKAlarm()
            alarm.structuredLocation = location
            alarm.proximity = place.proximity == .leave ? .leave : .enter
            alarms.append(alarm)
        }
        if !alarms.isEmpty {
            reminder.alarms = alarms
        }
    }

    nonisolated static func dueAlarm() -> EKAlarm {
        EKAlarm(relativeOffset: 0)
    }

    static func recurrence(_ rule: ReminderRepeat) -> EKRecurrenceRule {
        EKRecurrenceRule(recurrenceWith: frequency(rule.frequency), interval: rule.interval, end: nil)
    }

    static func frequency(_ value: ReminderRepeat.Frequency) -> EKRecurrenceFrequency {
        switch value {
        case .daily: return .daily
        case .weekly: return .weekly
        case .monthly: return .monthly
        case .yearly: return .yearly
        }
    }

    nonisolated static func storedSnapshots(_ reminders: [EKReminder]) -> [StoredReminder] {
        reminders.map { snapshot($0) }
    }

    static func snapshots() async -> [StoredReminder] {
        storedSnapshots(await store.fetchReminders())
    }

    nonisolated static func snapshot(_ reminder: EKReminder) -> StoredReminder {
        let parts = reminder.dueDateComponents
        let placeAlarm = reminder.alarms?.first { $0.structuredLocation != nil }
        return StoredReminder(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            list: reminder.calendar?.title ?? "",
            notes: reminder.notes ?? "",
            due: parts.flatMap { Calendar.current.date(from: $0) },
            allDay: parts.map { $0.hour == nil } ?? false,
            isCompleted: reminder.isCompleted,
            priority: priority(reminder.priority),
            place: placeAlarm?.structuredLocation?.title,
            proximity: placeAlarm.map { $0.proximity == .leave ? .leave : .arrive },
            repeatRule: reminder.recurrenceRules?.first.flatMap { repeatRule($0) }
        )
    }

    nonisolated static func priority(_ value: Int) -> ReminderPriority? {
        switch value {
        case 1...4: return .high
        case 6...9: return .low
        default: return nil
        }
    }

    nonisolated static func repeatRule(_ rule: EKRecurrenceRule) -> ReminderRepeat? {
        let value: ReminderRepeat.Frequency
        switch rule.frequency {
        case .daily: value = .daily
        case .weekly: value = .weekly
        case .monthly: value = .monthly
        case .yearly: value = .yearly
        @unknown default: return nil
        }
        return ReminderRepeat(frequency: value, interval: rule.interval)
    }
}
