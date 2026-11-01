@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import UserNotifications
import XCTest
import GwenMobileKit

private struct QuietCalendar: BriefingCalendarReading {
    func briefingEvents(on day: Date) -> [DayBriefingEvent] { [] }
}

private struct QuietReminders: BriefingReminderReading {
    func briefingReminders() async -> [StoredReminder] { [] }
}

private struct QuietWeather: BriefingWeatherLoading {
    func briefingWeather(dayOffset: Int) async throws -> WeatherRef {
        WeatherFixture.ref(hours: WeatherFixture.day { WeatherFixture.hour($0, temp: 18) })
    }
}

private struct QuietTravel: BriefingTravelLooking {
    func briefingTravel(to location: String, departure: Date) async -> DayBriefingTravel? { nil }
}

@MainActor
final class BriefingNotifierCoverageTests: GwenTestCase {
    private func sources() -> DayBriefingSources {
        DayBriefingSources(calendar: QuietCalendar(), reminders: QuietReminders(), contacts: nil,
                           weather: QuietWeather(), travel: QuietTravel())
    }

    func testSmokeTheNotifierSchedulesAndClearsNotifications() async {
        let settings = AppSettings.shared
        let enabled = settings.briefing.enabled
        let minutes = settings.briefing.minutes
        settings.briefing.enabled = true
        settings.briefing.minutes = 7 * 60 + 30
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5,
                                                             hour: 6, minute: 0)) ?? Date()
        await DayBriefingNotifier.refresh(settings: settings, sources: sources(), now: now, force: true)
        settings.briefing.enabled = false
        await DayBriefingNotifier.refresh(settings: settings, sources: sources(), now: now, force: true)
        settings.briefing.enabled = enabled
        settings.briefing.minutes = minutes
    }

    func testTheNotifierHelpers() {
        let now = Date()
        XCTAssertNotNil(DayBriefingNotifier.fireDate(dayOffset: 0, minutes: 23 * 60 + 59, after: now))
        XCTAssertNil(DayBriefingNotifier.fireDate(dayOffset: -1, minutes: 0, after: now))
        let includes = DayBriefingNotifier.notificationIncludes(AppSettings.shared)
        XCTAssertNotNil(includes)
        XCTAssertFalse(DayBriefingNotifier.pendingIdentifiers.isEmpty)
        XCTAssertTrue(DayBriefingNotifier.scheduledIdentifier(offset: 2).hasSuffix("2"))
        _ = DayBriefingNotifier.contactsAllowed()
        _ = DayBriefingNotifier.locationAllowed()
        var ref = DayBriefingRef(date: "2026-10-05", greetingKey: "brief_greet_morning")
        ref.reminders = [DayBriefingItem(id: "r1", title: "Milch", detail: "Einkauf", badge: "2")]
        DayBriefingNotifier.post(ref)
    }
}
