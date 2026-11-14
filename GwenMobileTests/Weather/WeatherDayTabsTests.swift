@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class WeatherDayTabsTests: GwenTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private var today: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 4)) ?? Date()
    }

    func testNearDaysStayConsecutive() {
        XCTAssertEqual(WeatherDayTabs.dates(selected: "2026-10-05", today: today, calendar: calendar),
                       ["2026-10-04", "2026-10-05", "2026-10-06"])
    }

    func testALaterDayBringsItsOwnDayAfter() {
        XCTAssertEqual(WeatherDayTabs.dates(selected: "2026-10-08", today: today, calendar: calendar),
                       ["2026-10-04", "2026-10-08", "2026-10-09"])
    }

    func testPastDaysClampToToday() {
        XCTAssertEqual(WeatherDayTabs.dates(selected: "2026-10-01", today: today, calendar: calendar),
                       ["2026-10-04", "2026-10-05", "2026-10-06"])
    }

    func testTheOffsetCountsDaysFromToday() {
        XCTAssertEqual(WeatherDayTabs.offset(of: "2026-10-08", today: today, calendar: calendar), 4)
        XCTAssertEqual(WeatherDayTabs.offset(of: "2026-10-04", today: today, calendar: calendar), 0)
    }
}
