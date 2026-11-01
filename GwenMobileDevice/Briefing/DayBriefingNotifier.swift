@testable import GwenMobileFeatureCore
import GwenMobileKit
import Contacts
import CoreLocation
import Foundation
import UserNotifications

@MainActor
enum DayBriefingNotifier {
    static let identifier = "gwen.briefing.daily"
    static let refreshedDayKey = "briefingRefreshedDay"
    private static var refreshTask: Task<Void, Never>?

    static var pendingIdentifiers: [String] {
        [identifier] + (0...2).map { scheduledIdentifier(offset: $0) }
    }

    static func scheduledIdentifier(offset: Int) -> String { identifier + "\(offset)" }

    static func contactsAllowed(
        status: CNAuthorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
    ) -> Bool {
        if status == .authorized { return true }
        if status == .limited { return true }
        return false
    }

    static func locationAllowed() -> Bool {
        let status = CLLocationManager().authorizationStatus
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }

    static func notificationIncludes(_ settings: AppSettings) -> DayBriefingIncludes {
        DayBriefingIncludes(weather: settings.briefing.weather && locationAllowed(),
                            reminders: settings.briefing.reminders,
                            birthdays: settings.briefing.birthdays && contactsAllowed(),
                            travel: false)
    }

    static func notificationContent(for ref: DayBriefingRef, day: BriefingDay) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = DayBriefingAnswers.notificationTitle()
        content.body = DayBriefingAnswers.notificationBody(ref)
        content.sound = .default
        content.userInfo = NotificationRoute.briefingInfo(day: day, date: ref.date)
        return content
    }

    static func post(_ ref: DayBriefingRef) {
        let request = UNNotificationRequest(identifier: identifier + ".now",
                                            content: notificationContent(for: ref,
                                                                         day: ref.selectedDay ?? .today),
                                            trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            flowMark("BRIEFING mitteilung fehler=\(error?.localizedDescription ?? "-")")
        }
    }

    static func preparePermission() {
        NotificationPermission.request(reporting: "BRIEFING mitteilung_erlaubt")
    }

    static func refresh(settings: AppSettings = .shared, sources: DayBriefingSources = .live(),
                        now: Date = Date(), force: Bool = false) async {
        let previous = refreshTask
        let task = Task { @MainActor in
            _ = await previous?.value
            await performRefresh(settings: settings, sources: sources, now: now, force: force)
        }
        refreshTask = task
        await task.value
    }

    private static func performRefresh(settings: AppSettings, sources: DayBriefingSources,
                                       now: Date, force: Bool) async {
        let center = UNUserNotificationCenter.current()
        guard settings.briefing.enabled else {
            center.removePendingNotificationRequests(withIdentifiers: pendingIdentifiers)
            return
        }
        let today = Formatters.stamp(now)
        if !force, UserDefaults.standard.string(forKey: refreshedDayKey) == today { return }
        center.removePendingNotificationRequests(withIdentifiers: pendingIdentifiers)
        let service = DayBriefingService(sources: sources, includes: notificationIncludes(settings))
        let minutes = settings.briefing.minutes
        async let first = plannedBriefing(offset: 0, service: service, minutes: minutes, now: now)
        async let second = plannedBriefing(offset: 1, service: service, minutes: minutes, now: now)
        async let third = plannedBriefing(offset: 2, service: service, minutes: minutes, now: now)
        let days = await [first, second, third].compactMap { $0 }
        var planned = 0
        var failed = 0
        for day in days {
            let ref = day.ref
            let content = notificationContent(for: ref, day: BriefingDay.at(offset: day.offset))
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: day.fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: scheduledIdentifier(offset: day.offset),
                                                           content: content, trigger: trigger))
                planned += 1
            } catch {
                failed += 1
                flowMark("BRIEFING mitteilung planung fehlgeschlagen "
                         + "grund=\(TextLine.oneLine(error.localizedDescription, limit: 120))")
            }
        }
        if failed == 0 { UserDefaults.standard.set(today, forKey: refreshedDayKey) }
        flowMark("BRIEFING mitteilungen geplant=\(planned) fehler=\(failed) uhrzeit=\(Formatters.time(now))")
    }

    private struct PlannedBriefing {
        let offset: Int
        let fire: Date
        let ref: DayBriefingRef
    }

    private static func plannedBriefing(offset: Int, service: DayBriefingService,
                                        minutes: Int, now: Date) async -> PlannedBriefing? {
        guard let fire = fireDate(dayOffset: offset, minutes: minutes, after: now) else { return nil }
        let ref = await service.build(BriefingDay.at(offset: offset), now: now)
        return PlannedBriefing(offset: offset, fire: fire, ref: ref)
    }

    nonisolated static func fireDate(dayOffset: Int, minutes: Int, after now: Date,
                                     system: Calendar = .current) -> Date? {
        guard let day = system.date(byAdding: .day, value: dayOffset, to: system.startOfDay(for: now)) else {
            return nil
        }
        var parts = system.dateComponents([.year, .month, .day], from: day)
        parts.hour = minutes / 60
        parts.minute = minutes % 60
        guard let fire = system.date(from: parts), fire > now else { return nil }
        return fire
    }
}
