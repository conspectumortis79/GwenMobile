import Foundation
import EventKit

@MainActor
enum CalendarService {
    static let eventDateTimeFormat = "yyyy-MM-dd HH:mm"
    static let lookbackDays = 7
    static let lookaheadDays = 60
    static let findWindowPastDays = 40
    static let findWindowFutureDays = 400
    static let contextEventLimit = 15
    static let defaultDurationMinutes = 30
    static let minAlertMinutes = 1
    static let maxAlertMinutes = 7 * 24 * 60

    private static let store = EKEventStore()

    static func ensureAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess: return true
        case .notDetermined:
            do { return try await store.requestFullAccessToEvents() }
            catch { return false }
        default: return false
        }
    }

    static func upcomingContext() -> String {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return "" }
        let fmt = dateTimeFormatter()
        let secondsPerDay = 86400.0
        let predicate = store.predicateForEvents(withStart: Date().addingTimeInterval(-Double(lookbackDays) * secondsPerDay),
                                                 end: Date().addingTimeInterval(Double(lookaheadDays) * secondsPerDay),
                                                 calendars: nil)
        let events = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .prefix(contextEventLimit)
        return events.map { ev in
            let mins = alertMinutes(for: ev)
            let alerts = mins.isEmpty ? "none" : mins.map { "\($0) min before" }.joined(separator: ", ")
            return "- \(ev.title ?? "") — \(fmt.string(from: ev.startDate)) — notifications: \(alerts)"
        }.joined(separator: "\n")
    }

    static func perform(_ plan: QwenAPI.CalendarPlan) async throws -> String {
        guard await ensureAccess() else { throw APIError(message: L.t("cal_denied")) }
        let fmt = dateTimeFormatter()

        switch plan.action {
        case .create:
            guard let start = plan.start.flatMap({ fmt.date(from: $0) }) else {
                throw APIError(message: L.t("cal_no_date"))
            }
            let end = plan.end.flatMap { fmt.date(from: $0) } ?? start.addingTimeInterval(Double(defaultDurationMinutes) * 60)
            let ev = EKEvent(eventStore: store)
            ev.title = plan.title ?? L.t("cal_default_title")
            ev.startDate = start
            ev.endDate = end
            ev.calendar = store.defaultCalendarForNewEvents
            if let loc = plan.location { ev.location = loc }
            if let notes = plan.notes { ev.notes = notes }
            if let alerts = plan.alerts { ev.alarms = alarms(minutesBefore: alerts, for: ev) }
            try store.save(ev, span: .thisEvent)
            return L.fmt("cal_created", describe(ev))
        case .update:
            let ev = try find(plan.find ?? plan.title)
            let keepMinutes = alertMinutes(for: ev)
            let oldStart = ev.startDate
            if let t = plan.title { ev.title = t }
            if let start = plan.start.flatMap({ fmt.date(from: $0) }) {
                let dur = max(60, ev.endDate.timeIntervalSince(ev.startDate))
                ev.startDate = start
                ev.endDate = plan.end.flatMap({ fmt.date(from: $0) }) ?? start.addingTimeInterval(dur)
            }
            if let loc = plan.location { ev.location = loc }
            if let notes = plan.notes { ev.notes = notes }
            if let alerts = plan.alerts {
                ev.alarms = alarms(minutesBefore: alerts, for: ev)
            } else if ev.startDate != oldStart, !keepMinutes.isEmpty {
                ev.alarms = alarms(minutesBefore: keepMinutes, for: ev)
            }
            try store.save(ev, span: .thisEvent)
            return L.fmt("cal_updated", describe(ev))
        case .delete:
            let ev = try find(plan.find ?? plan.title)
            let desc = describe(ev)
            try store.remove(ev, span: .thisEvent)
            return L.fmt("cal_deleted", desc)
        case .none:
            return ""
        }
    }

    private static func dateTimeFormatter() -> DateFormatter {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = eventDateTimeFormat
        return fmt
    }

    private static func alarms(minutesBefore: [Int], for ev: EKEvent) -> [EKAlarm] {
        let valid = Set(minutesBefore.filter { $0 >= minAlertMinutes && $0 <= maxAlertMinutes })
        return valid.sorted().map { EKAlarm(absoluteDate: ev.startDate.addingTimeInterval(-Double($0) * 60)) }
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

    private static func find(_ query: String?) throws -> EKEvent {
        let secondsPerDay = 86400.0
        let from = Date().addingTimeInterval(-Double(findWindowPastDays) * secondsPerDay)
        let to = Date().addingTimeInterval(Double(findWindowFutureDays) * secondsPerDay)
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        var events = store.events(matching: predicate)
        let q = (query ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            let words = q.split(separator: " ").map(String.init)
            let hits = events.filter { ev in
                let hay = ((ev.title ?? "") + " " + (ev.location ?? "") + " " + (ev.notes ?? "")).lowercased()
                return words.contains { hay.contains($0) }
            }
            events = hits.isEmpty ? events : hits
        }
        events.sort { abs($0.startDate.timeIntervalSinceNow) < abs($1.startDate.timeIntervalSinceNow) }
        guard let ev = events.first else { throw APIError(message: L.t("cal_not_found") + (query ?? "?")) }
        return ev
    }

    private static func describe(_ ev: EKEvent) -> String {
        let d = DateFormatter()
        d.locale = L.lang.locale
        d.dateFormat = L.calStartFormat
        let endFmt = DateFormatter()
        endFmt.locale = L.lang.locale
        endFmt.dateFormat = L.timeFormat
        var s = "\(ev.title ?? "") — \(d.string(from: ev.startDate))–\(endFmt.string(from: ev.endDate))"
        if let loc = ev.location, !loc.isEmpty { s += " · \(loc)" }
        if let alerts = alertSummary(for: ev) { s += "\n\(alerts)" }
        return s
    }
}
