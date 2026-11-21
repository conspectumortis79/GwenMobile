@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class ReminderChipTests: GwenTestCase {
    func testAStampShowsTheDueTimeWhenThereIsOne() {
        let due = Formatters.eventDate(from: "2026-10-08 09:00")!
        let ref = ReminderRef(StoredReminder(id: "r1", title: "Zahnarzt", list: "Erinnerungen", due: due))
        XCTAssertEqual(ref.chipStamp, Formatters.eventChip(due))
        XCTAssertTrue(ref.isOpenable)
    }

    func testAnAllDayStampShowsTheDay() {
        let due = Formatters.eventDay(from: "2026-10-08")!
        let ref = ReminderRef(StoredReminder(id: "r1", title: "Reifen", list: "Erinnerungen",
                                             due: due, allDay: true))
        XCTAssertEqual(ref.chipStamp, Formatters.day(due))
    }

    func testWithoutADueDateThePlaceOrListNamesTheReminder() {
        let placed = ReminderRef(StoredReminder(id: "r1", title: "Milch", list: "Erinnerungen", place: "REWE"))
        XCTAssertEqual(placed.chipStamp, "REWE")
        let plain = ReminderRef(StoredReminder(id: "r2", title: "Milch", list: "Einkauf"))
        XCTAssertEqual(plain.chipStamp, "Einkauf")
    }

    func testAnEmptyIdentifierIsNotOpenable() {
        let ref = ReminderRef(StoredReminder(id: "", title: "Milch", list: "Einkauf"))
        XCTAssertFalse(ref.isOpenable)
        XCTAssertEqual(ReminderChip.outcome(for: ref, hasAccess: true, isLive: { _ in true }), .gone)
    }

    func testMissingAccessAndAGoneReminderHaveTheirOwnNotice() {
        let ref = ReminderRef(StoredReminder(id: "r1", title: "Milch", list: "Einkauf"))
        XCTAssertEqual(ReminderChip.outcome(for: ref, hasAccess: false, isLive: { _ in true }), .accessMissing)
        XCTAssertEqual(ReminderChip.noticeKey(for: .accessMissing), "rem_denied")
        XCTAssertEqual(ReminderChip.outcome(for: ref, hasAccess: true, isLive: { _ in false }), .gone)
        XCTAssertEqual(ReminderChip.noticeKey(for: .gone), "rem_chip_gone")
    }

    func testTheStoredRefDecodesWithoutEveryField() throws {
        let data = Data(#"{"reminderID":"r1","title":"Milch"}"#.utf8)
        let ref = try JSONDecoder().decode(ReminderRef.self, from: data)
        XCTAssertEqual(ref.reminderID, "r1")
        XCTAssertEqual(ref.title, "Milch")
        XCTAssertEqual(ref.list, "")
        XCTAssertNil(ref.due)
        XCTAssertFalse(ref.allDay)
    }

    func testTheDefaultTitleIsUsedForAnEmptyChipTitle() {
        let ref = ReminderRef(StoredReminder(id: "r1", title: "", list: "Einkauf"))
        XCTAssertEqual(ref.chipTitle, L.t("rem_default_title"))
    }

    func testTheRemindersLinkUsesTheSchemeThatOpensTheApp() {
        XCTAssertEqual(ReminderChip.remindersURLs.first?.scheme, "x-apple-reminderkit")
        XCTAssertEqual(ReminderChip.remindersURLs.last?.scheme, "x-apple-reminder")
        XCTAssertFalse(ReminderChip.remindersURLs.isEmpty)
    }
}
