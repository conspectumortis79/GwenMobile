import GwenMobileKit
import Foundation
import EventKit

extension QwenAPI.CalendarPlan {
    var needsPlannerPass: Bool { action == .create }

    var needsExistingEvent: Bool { action == .update || action == .delete }

    var lookupWords: String { find ?? title ?? "" }

    var givenTitle: String? {
        let named = title?.trimmed ?? ""
        return named.isEmpty ? nil : named
    }

    var eventTitle: String { givenTitle ?? L.t("cal_default_title") }

    var startDate: Date? { start.flatMap { Formatters.eventDate(from: $0) } }

    var stepWords: String {
        [action.rawValue, title ?? "", find ?? "", start ?? ""].joined(separator: " ")
    }
}

@MainActor
protocol CalendarEventStoring {
    func makeEvent() -> EKEvent
    func events(matching predicate: NSPredicate) -> [EKEvent]
    func predicateForEvents(withStart start: Date, end: Date, calendars: [EKCalendar]?) -> NSPredicate
    func event(withIdentifier identifier: String) -> EKEvent?
    func remove(_ event: EKEvent, span: EKSpan) throws
    func save(_ event: EKEvent, span: EKSpan) throws
    func requestFullAccessToEvents() async throws -> Bool
    func calendars(for entityType: EKEntityType) -> [EKCalendar]
    var defaultCalendarForNewEvents: EKCalendar? { get }
}

@MainActor
final class LiveCalendarEventStore: CalendarEventStoring {
    static let shared = LiveCalendarEventStore()
    private let store = EKEventStore()

    func makeEvent() -> EKEvent { EKEvent(eventStore: store) }

    func events(matching predicate: NSPredicate) -> [EKEvent] { store.events(matching: predicate) }

    func predicateForEvents(withStart start: Date, end: Date, calendars: [EKCalendar]?) -> NSPredicate {
        store.predicateForEvents(withStart: start, end: end, calendars: calendars)
    }

    func event(withIdentifier identifier: String) -> EKEvent? { store.event(withIdentifier: identifier) }

    func remove(_ event: EKEvent, span: EKSpan) throws { try store.remove(event, span: span) }

    func save(_ event: EKEvent, span: EKSpan) throws { try store.save(event, span: span) }

    func requestFullAccessToEvents() async throws -> Bool { try await store.requestFullAccessToEvents() }

    func calendars(for entityType: EKEntityType) -> [EKCalendar] { store.calendars(for: entityType) }

    var defaultCalendarForNewEvents: EKCalendar? { store.defaultCalendarForNewEvents }
}

@MainActor
enum CalendarService {
    static let lookbackDays = 7
    static let lookaheadDays = 60
    static let findWindowPastDays = 40
    static let findWindowFutureDays = 400
    static let contextEventLimit = 15
    static let defaultDurationMinutes = 30
    static let minAlertMinutes = 1
    static let maxAlertMinutes = 7 * 24 * 60
    static let secondsPerDay = 86400.0

    nonisolated(unsafe) static var storeOverride: (any CalendarEventStoring)?

    static var store: any CalendarEventStoring { storeOverride ?? LiveCalendarEventStore.shared }

    nonisolated(unsafe) static var accessStatusOverride: EKAuthorizationStatus?
    nonisolated(unsafe) static var eventsOverride: ((Date, Date) -> [EKEvent])?

    static func query(from: Date, to: Date) -> [EKEvent] {
        if let eventsOverride { return eventsOverride(from, to) }
        return store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: nil))
    }

    static var hasAccess: Bool { accessStatus == .fullAccess }

    static var accessStatus: EKAuthorizationStatus {
        accessStatusOverride ?? EKEventStore.authorizationStatus(for: .event)
    }

    static func event(withIdentifier eventID: String) -> EKEvent? {
        guard hasAccess, !eventID.isEmpty else { return nil }
        return store.event(withIdentifier: eventID)
    }

    static func isLive(_ eventID: String) -> Bool { event(withIdentifier: eventID) != nil }

    static func event(for ref: CalendarRef) -> EKEvent? { event(withIdentifier: ref.eventID) }

    #if DEBUG
    @discardableResult
    static func remove(eventID: String) throws -> Bool {
        guard let event = event(withIdentifier: eventID) else { return false }
        try store.remove(event, span: .thisEvent)
        return true
    }
    #endif

    static func ensureAccess() async -> Bool {
        let status = accessStatus
        switch status {
        case .fullAccess: return true
        case .notDetermined:
            do { return try await store.requestFullAccessToEvents() }
            catch { return false }
        default: return false
        }
    }

    static func calendarTitles() -> [String] {
        guard hasAccess else { return [] }
        return store.calendars(for: .event).filter { $0.allowsContentModifications }.map { $0.title }
    }

    #if DEBUG
    static var writableCalendarCount: Int {
        store.calendars(for: .event).filter { $0.allowsContentModifications }.count
    }
    #endif

    static func calendarsContext() -> String {
        let titles = calendarTitles()
        guard !titles.isEmpty else { return "" }
        return "\nYour writable calendars (use one exact title for \"calendar\"): \(titles.joined(separator: ", ")).\n"
    }

    static func upcomingContext(now: Date = Date()) -> String {
        guard hasAccess else { return "" }
        let from = now.addingTimeInterval(-Double(lookbackDays) * secondsPerDay)
        let to = now.addingTimeInterval(Double(lookaheadDays) * secondsPerDay)
        let events = upcoming(query(from: from, to: to), now: now,
                              start: { $0.startDate }, end: { $0.endDate })
        return events.map { ev in
            let mins = alertMinutes(for: ev)
            let alerts = mins.isEmpty ? "none" : mins.map { "\($0) min before" }.joined(separator: ", ")
            return "- \(ev.title ?? "") — \(Formatters.eventDateTime(ev.startDate)) — notifications: \(alerts) — calendar: \(ev.calendar.title)"
        }.joined(separator: "\n")
    }

    static func upcoming<Item>(_ items: [Item], now: Date,
                               start: (Item) -> Date, end: (Item) -> Date,
                               limit: Int = contextEventLimit) -> [Item] {
        items.filter { end($0) >= now }
            .sorted { start($0) < start($1) }
            .prefix(limit)
            .map { $0 }
    }

    static func perform(_ plan: QwenAPI.CalendarPlan) async throws -> CalendarOutcome {
        guard await ensureAccess() else {
            throw APIError(message: L.t(accessStatus == .writeOnly ? "cal_denied_write_only"
                                                                   : "cal_denied"))
        }

        switch plan.action {
        case .create:
            guard let start = plan.startDate else {
                throw APIError(message: L.t("cal_no_date"))
            }
            let end = plan.end.flatMap { Formatters.eventDate(from: $0) }
                .flatMap { $0 > start ? $0 : nil }
                ?? start.addingTimeInterval(Double(defaultDurationMinutes) * 60)
            let ev = store.makeEvent()
            ev.title = plan.eventTitle
            ev.startDate = start
            ev.endDate = end
            ev.calendar = try targetCalendar(requested: plan.calendar, current: store.defaultCalendarForNewEvents,
                                             silent: .deviceDefault)
            if let loc = plan.location { ev.location = loc }
            if let notes = plan.notes { ev.notes = notes }
            if let alerts = plan.alerts { ev.alarms = alarms(minutesBefore: alerts) }
            try store.save(ev, span: .thisEvent)
            return CalendarOutcome(notice: L.fmt("cal_created", describe(ev)), ref: reference(for: ev))
        case .update:
            let ev = try find(plan.find ?? plan.title)
            let keepMinutes = alertMinutes(for: ev)
            let oldStart = ev.startDate
            if let t = plan.givenTitle { ev.title = t }
            if let start = plan.start.flatMap({ Formatters.eventDate(from: $0) }) {
                let running = ev.endDate.timeIntervalSince(ev.startDate)
                let dur = running > 0 ? running : Double(defaultDurationMinutes) * 60
                ev.startDate = start
                let askedEnd = plan.end.flatMap { Formatters.eventDate(from: $0) }
                ev.endDate = askedEnd.flatMap { $0 > start ? $0 : nil } ?? start.addingTimeInterval(dur)
            } else if let end = plan.end.flatMap({ Formatters.eventDate(from: $0) }), end > ev.startDate {
                ev.endDate = end
            }
            if let loc = plan.location { ev.location = loc }
            if let notes = plan.notes { ev.notes = notes }
            if let wanted = plan.calendar {
                ev.calendar = try targetCalendar(requested: wanted, current: ev.calendar, silent: .keepCurrent)
            }
            if let alerts = plan.alerts {
                ev.alarms = alarms(minutesBefore: alerts)
            } else if ev.startDate != oldStart, !keepMinutes.isEmpty {
                ev.alarms = alarms(minutesBefore: keepMinutes)
            }
            try store.save(ev, span: .thisEvent)
            return CalendarOutcome(notice: L.fmt("cal_updated", describe(ev)), ref: reference(for: ev))
        case .delete:
            let ev = try find(plan.find ?? plan.title, requiresTitle: true)
            let desc = describe(ev)
            try store.remove(ev, span: .thisEvent)
            return CalendarOutcome(notice: L.fmt("cal_deleted", desc), ref: nil)
        case .none:
            return CalendarOutcome(notice: "", ref: nil)
        }
    }

    static func events(on day: Date, calendar: Calendar = .current) -> [EKEvent] {
        guard hasAccess, let interval = calendar.dateInterval(of: .day, for: day) else { return [] }
        return query(from: interval.start, to: interval.end).sorted { left, right in
            if left.isAllDay != right.isAllDay { return !left.isAllDay }
            return left.startDate < right.startDate
        }
    }

    static func reference(for ev: EKEvent) -> CalendarRef? {
        reference(id: ev.eventIdentifier, title: ev.title, start: ev.startDate)
    }

    static func reference(id: String?, title: String?, start: Date) -> CalendarRef? {
        guard let id, !id.isEmpty else { return nil }
        return CalendarRef(eventID: id, title: title ?? "", start: start)
    }

    static func targetCalendar(requested: String?, current: EKCalendar?,
                                       silent: CalendarChoice.Silent) throws -> EKCalendar {
        let candidates = store.calendars(for: .event).filter { $0.allowsContentModifications }
        let titles = candidates.map { $0.title }
        let outcome = CalendarChoice.resolve(requested: requested, available: titles,
                                             deviceDefault: store.defaultCalendarForNewEvents?.title,
                                             silent: silent)
        switch outcome {
        case .keep:
            guard let current else { throw APIError(message: L.t("cal_no_calendar")) }
            return current
        case .title(let chosen):
            return try calendar(named: chosen, in: candidates, titles: titles)
        case .unmatched(let asked):
            throw APIError(message: L.fmt2("cal_calendar_missing", asked, titles.joined(separator: ", ")))
        }
    }

    static func calendar(named chosen: String, in candidates: [EKCalendar], titles: [String]) throws -> EKCalendar {
        guard let candidate = candidates.first(where: { $0.title == chosen }) else {
            throw APIError(message: L.fmt2("cal_calendar_missing", chosen, titles.joined(separator: ", ")))
        }
        return candidate
    }

    static func alarms(minutesBefore: [Int]) -> [EKAlarm] {
        let valid = Set(minutesBefore.filter { $0 >= minAlertMinutes && $0 <= maxAlertMinutes })
        return valid.sorted().map { EKAlarm(relativeOffset: -Double($0) * 60) }
    }

    static func alertMinutes(for ev: EKEvent) -> [Int] {
        (ev.alarms ?? [])
            .compactMap { alarm -> Int? in
                if let date = alarm.absoluteDate {
                    return Int((ev.startDate.timeIntervalSince(date) / 60).rounded())
                }
                return Int((alarm.relativeOffset / -60).rounded())
            }
            .filter { $0 >= minAlertMinutes }
            .sorted()
    }

    static func alertSummary(for ev: EKEvent) -> String? {
        let mins = alertMinutes(for: ev)
        guard !mins.isEmpty else { return nil }
        let parts = mins.map { m -> String in
            if m >= 60, m % 60 == 0 { return L.n("cal_alert_h", m / 60) }
            return L.n("cal_alert_min", m)
        }
        return L.fmt("cal_alerts", parts.joined(separator: ", "))
    }

    static func matches(_ plan: QwenAPI.CalendarPlan) -> Bool {
        let asked = plan.lookupWords.trimmed
        return CalendarMatching.bestIndex(in: searchableEvents().candidates, query: asked, now: Date(),
                                          requiresTitle: plan.action == .delete) != nil
    }

    static func find(_ query: String?, requiresTitle: Bool = false) throws -> EKEvent {
        let searchable = searchableEvents()
        let asked = query?.trimmed ?? ""
        guard let index = CalendarMatching.bestIndex(in: searchable.candidates, query: asked, now: Date(),
                                                    requiresTitle: requiresTitle) else {
            throw APIError(message: L.t("cal_not_found") + (asked.isEmpty ? "?" : asked))
        }
        return searchable.events[index]
    }

    static func searchableEvents() -> (events: [EKEvent], candidates: [CalendarMatch]) {
        let from = Date().addingTimeInterval(-Double(findWindowPastDays) * secondsPerDay)
        let to = Date().addingTimeInterval(Double(findWindowFutureDays) * secondsPerDay)
        let events = query(from: from, to: to)
        let candidates = events.map { event in
            CalendarMatch(title: event.title ?? "", location: event.location ?? "",
                          notes: event.notes ?? "", start: event.startDate)
        }
        return (events, candidates)
    }

    static func describe(_ ev: EKEvent) -> String {
        var s = "\(ev.title ?? "") — \(Formatters.eventStart(ev.startDate))–\(Formatters.time(ev.endDate))"
        if let loc = ev.location, !loc.isEmpty { s += " · \(loc)" }
        s += "\n" + L.fmt("cal_calendar", ev.calendar.title)
        if let alerts = alertSummary(for: ev) { s += "\n\(alerts)" }
        return s
    }
}
