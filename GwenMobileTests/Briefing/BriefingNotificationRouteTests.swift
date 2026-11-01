@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import UserNotifications
import XCTest
import GwenMobileKit

@MainActor
final class BriefingNotificationRouteTests: GwenTestCase {
    private func date(_ day: Int, hour: Int = 8) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour)) ?? Date()
    }

    func testTheNotificationCarriesTheBriefingTarget() {
        var ref = DayBriefingRef(date: "2026-10-06", greetingKey: "brief_greet_tomorrow")
        ref.reminders = [DayBriefingItem(id: "r1", title: "Milch", detail: "Einkauf")]
        let content = DayBriefingNotifier.notificationContent(for: ref, day: .tomorrow)
        XCTAssertEqual(content.userInfo[NotificationRoute.key] as? String, NotificationRoute.briefing)
        XCTAssertEqual(content.userInfo[NotificationRoute.dayKey] as? String, BriefingDay.tomorrow.rawValue)
        XCTAssertEqual(content.userInfo[NotificationRoute.dateKey] as? String, "2026-10-06")
        XCTAssertEqual(NotificationRoute.briefingDay(in: content.userInfo, now: date(5)), .tomorrow)
    }

    func testAnOldNotificationOpensToday() {
        let info = NotificationRoute.briefingInfo(day: .dayAfter, date: "2026-10-01")
        XCTAssertEqual(NotificationRoute.briefingDay(in: info, now: date(5)), .today)
    }

    func testAForeignNotificationIsIgnored() {
        XCTAssertNil(NotificationRoute.briefingDay(in: [:], now: date(5)))
        XCTAssertNil(NotificationRoute.briefingDay(in: [NotificationRoute.key: "timer"], now: date(5)))
    }

    func testANotificationWithoutADateUsesTheDayKey() {
        let known: [AnyHashable: Any] = [NotificationRoute.key: NotificationRoute.briefing,
                                         NotificationRoute.dayKey: BriefingDay.dayAfter.rawValue]
        XCTAssertEqual(NotificationRoute.briefingDay(in: known, now: date(5)), .dayAfter)
        let unknown: [AnyHashable: Any] = [NotificationRoute.key: NotificationRoute.briefing,
                                           NotificationRoute.dayKey: "irgendwann"]
        XCTAssertEqual(NotificationRoute.briefingDay(in: unknown, now: date(5)), .today)
        let bare: [AnyHashable: Any] = [NotificationRoute.key: NotificationRoute.briefing]
        XCTAssertEqual(NotificationRoute.briefingDay(in: bare, now: date(5)), .today)
    }

    func testTheOpenRequestAdvancesOnce() {
        let requests = BriefingOpenRequests()
        XCTAssertEqual(requests.token, 0)
        XCTAssertEqual(requests.day, .today)
        requests.ask(day: .dayAfter)
        XCTAssertEqual(requests.token, 1)
        XCTAssertEqual(requests.day, .dayAfter)
    }
}
