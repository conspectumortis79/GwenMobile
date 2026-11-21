@testable import GwenMobileFeatureCore
import EventKit
import XCTest

final class EventKitReminderAlarmTests: GwenTestCase {
    func testTheDueAlarmFollowsTheRemindersWallClockTime() {
        let alarm = EventKitReminderStore.dueAlarm()
        XCTAssertNil(alarm.absoluteDate)
        XCTAssertEqual(alarm.relativeOffset, 0)
    }
}
