@testable import GwenMobileFeatureCore
import Contacts
import XCTest
import GwenMobileKit

final class DayBriefingNotifierTests: GwenTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))
            ?? .distantPast
    }

    func testTheFireDateKeepsFutureTimesForEachDayOffset() {
        let now = date(2026, 10, 8, 7, 0)
        XCTAssertEqual(DayBriefingNotifier.fireDate(dayOffset: 0, minutes: 7 * 60 + 30, after: now,
                                                    system: calendar),
                       date(2026, 10, 8, 7, 30))
        XCTAssertEqual(DayBriefingNotifier.fireDate(dayOffset: 1, minutes: 7 * 60 + 30, after: now,
                                                    system: calendar),
                       date(2026, 10, 9, 7, 30))
        XCTAssertEqual(DayBriefingNotifier.fireDate(dayOffset: 2, minutes: 7 * 60 + 30, after: now,
                                                    system: calendar),
                       date(2026, 10, 10, 7, 30))
    }

    func testTheFireDateSkipsTimesThatAlreadyPassed() {
        let now = date(2026, 10, 8, 8, 0)
        XCTAssertNil(DayBriefingNotifier.fireDate(dayOffset: 0, minutes: 7 * 60 + 30, after: now,
                                                  system: calendar))
        XCTAssertEqual(DayBriefingNotifier.fireDate(dayOffset: 1, minutes: 7 * 60 + 30, after: now,
                                                    system: calendar),
                       date(2026, 10, 9, 7, 30))
    }

    func testTheCurrentMomentIsNeverScheduledAgain() {
        let now = date(2026, 10, 8, 7, 30)
        XCTAssertNil(DayBriefingNotifier.fireDate(dayOffset: 0, minutes: 7 * 60 + 30, after: now,
                                                  system: calendar))
    }

    func testTheFireDateKeepsTheWallClockAcrossDaylightSavingChanges() {
        let springNow = date(2026, 3, 29, 6, 0)
        let spring = DayBriefingNotifier.fireDate(dayOffset: 0, minutes: 7 * 60 + 30, after: springNow,
                                                  system: calendar)
        XCTAssertEqual(spring, date(2026, 3, 29, 7, 30))
        XCTAssertEqual(spring.map { calendar.component(.hour, from: $0) }, 7)
        XCTAssertEqual(spring.map { calendar.component(.minute, from: $0) }, 30)

        let autumnNow = date(2026, 10, 25, 6, 0)
        let autumn = DayBriefingNotifier.fireDate(dayOffset: 0, minutes: 7 * 60 + 30, after: autumnNow,
                                                  system: calendar)
        XCTAssertEqual(autumn, date(2026, 10, 25, 7, 30))
        XCTAssertEqual(autumn.map { calendar.component(.hour, from: $0) }, 7)
        XCTAssertEqual(autumn.map { calendar.component(.minute, from: $0) }, 30)
    }

    func testAFireTimeInsideTheSpringForwardGapMovesPastTheGap() {
        let now = date(2026, 3, 29, 0, 0)
        let fire = DayBriefingNotifier.fireDate(dayOffset: 0, minutes: 2 * 60 + 30, after: now,
                                                system: calendar)
        XCTAssertNotNil(fire)
        XCTAssertEqual(fire.map { calendar.component(.hour, from: $0) }, 3)
        XCTAssertEqual(fire.map { calendar.component(.minute, from: $0) }, 30)
    }

    @MainActor func testLimitedContactsStillSupplyTheBirthdaySection() {
        XCTAssertTrue(DayBriefingNotifier.contactsAllowed(status: .authorized))
        XCTAssertTrue(DayBriefingNotifier.contactsAllowed(status: .limited))
        XCTAssertFalse(DayBriefingNotifier.contactsAllowed(status: .denied))
        XCTAssertFalse(DayBriefingNotifier.contactsAllowed(status: .notDetermined))
    }

    @MainActor func testEveryScheduledDayIsCancelledTogetherWithTheBriefing() {
        XCTAssertTrue(DayBriefingNotifier.pendingIdentifiers
            .contains(DayBriefingNotifier.immediateIdentifier))
        for offset in 0...2 {
            XCTAssertTrue(DayBriefingNotifier.pendingIdentifiers
                .contains(DayBriefingNotifier.scheduledIdentifier(offset: offset)))
        }
        XCTAssertEqual(Set(DayBriefingNotifier.pendingIdentifiers).count,
                       DayBriefingNotifier.pendingIdentifiers.count)
    }

    @MainActor func testFutureScheduledBriefingsGreetAsMorningAndUseFireTimeForOverdue() async throws {
        struct ReminderStub: BriefingReminderReading {
            let items: [StoredReminder]
            func briefingReminders() async -> [StoredReminder] { items }
        }
        struct CalendarStub: BriefingCalendarReading {
            func briefingEvents(on day: Date) -> [DayBriefingEvent] { [] }
        }
        final class WeatherSpy: BriefingWeatherLoading {
            private(set) var offsets: [Int] = []
            func briefingWeather(dayOffset: Int) async throws -> WeatherRef {
                offsets.append(dayOffset)
                return WeatherFixture.ref(hours: WeatherFixture.day { WeatherFixture.hour($0, temp: 15) })
            }
        }
        let now = date(2026, 10, 8, 10, 0)
        let dueTodayAfternoon = date(2026, 10, 8, 15, 0)
        let weather = WeatherSpy()
        let sources = DayBriefingSources(
            calendar: CalendarStub(),
            reminders: ReminderStub(items: [StoredReminder(id: "r1", title: "Steuer", list: "Privat",
                                                           due: dueTodayAfternoon)]),
            contacts: nil, weather: weather, travel: nil)
        let service = DayBriefingService(sources: sources, includes: DayBriefingIncludes())
        let result = await DayBriefingNotifier.plannedBriefing(
            offset: 1, service: service, minutes: 7 * 60 + 30, now: now)
        let planned = try XCTUnwrap(result)
        XCTAssertEqual(planned.ref.greetingKey, "brief_greet_morning")
        XCTAssertEqual(planned.ref.date, "2026-10-09")
        XCTAssertEqual(weather.offsets, [1])
        XCTAssertEqual(planned.ref.reminders.first?.title, "Steuer")
        XCTAssertEqual(planned.ref.reminders.first?.overdue, true)
    }
}
