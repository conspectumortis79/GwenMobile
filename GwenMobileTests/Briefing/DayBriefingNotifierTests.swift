@testable import GwenMobileDevice
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
        for offset in 0...2 {
            XCTAssertTrue(DayBriefingNotifier.pendingIdentifiers
                .contains(DayBriefingNotifier.scheduledIdentifier(offset: offset)))
        }
        XCTAssertEqual(Set(DayBriefingNotifier.pendingIdentifiers).count,
                       DayBriefingNotifier.pendingIdentifiers.count)
    }
}
