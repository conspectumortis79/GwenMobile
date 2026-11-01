@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class CalendarChipTests: GwenTestCase {
    private let ref = CalendarRef(eventID: "ID-1", title: "Zahnarzt",
                                  start: Date(timeIntervalSince1970: 1_800_000_000))

    private func outcome(hasAccess: Bool, live: Set<String>) -> CalendarChipOutcome {
        CalendarChip.outcome(for: ref, hasAccess: hasAccess, isLive: { id in live.contains(id) })
    }

    func testALivingEventOpens() {
        XCTAssertEqual(outcome(hasAccess: true, live: ["ID-1"]), .present(ref))
        XCTAssertNil(CalendarChip.noticeKey(for: .present(ref)))
    }

    func testAMissingEventIsReportedAsGone() {
        XCTAssertEqual(outcome(hasAccess: true, live: []), .gone)
        XCTAssertEqual(CalendarChip.noticeKey(for: .gone), "cal_chip_gone")
    }

    func testWithoutCalendarAccessTheChipPointsAtTheSettings() {
        XCTAssertEqual(outcome(hasAccess: false, live: ["ID-1"]), .accessMissing)
        XCTAssertEqual(CalendarChip.noticeKey(for: .accessMissing), "cal_denied")
    }

    func testTheCalendarIsNotSearchedWithoutAccess() {
        var asked = false
        let result = CalendarChip.outcome(for: ref, hasAccess: false,
                                         isLive: { _ in asked = true; return true })
        XCTAssertEqual(result, .accessMissing)
        XCTAssertFalse(asked, "ohne Zugriff bringt das Nachschauen nichts")
    }

    func testARefWithoutIdentifierNeverReachesTheCalendar() {
        var asked = false
        let dead = CalendarRef(eventID: "", title: "Zahnarzt", start: Date(timeIntervalSince1970: 0))
        let result = CalendarChip.outcome(for: dead, hasAccess: true,
                                         isLive: { _ in asked = true; return true })
        XCTAssertEqual(result, .gone)
        XCTAssertFalse(asked)
    }

    func testEveryOutcomeHasExactlyOneNoticeKey() {
        let outcomes: [CalendarChipOutcome] = [.present(ref), .accessMissing, .gone]
        let keys = outcomes.compactMap { CalendarChip.noticeKey(for: $0) }
        XCTAssertEqual(Set(keys).count, 2, "offnen braucht keine Meldung, die zwei anderen je eine eigene")
        for key in keys { XCTAssertNotEqual(L.t(key), key, "\(key) fehlt in der Übersetzung") }
    }

    func testTheOnlyWayIntoTheCalendarAppIsTheTodayLink() {
        XCTAssertEqual(CalendarChip.todayURL?.scheme, "calshow")
        XCTAssertEqual(CalendarChip.todayURL?.absoluteString, "calshow://")
    }
}
