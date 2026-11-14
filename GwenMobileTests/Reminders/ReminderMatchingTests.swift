@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class ReminderMatchingTests: GwenTestCase {
    private let now = Formatters.eventDate(from: "2026-10-07 15:00")!

    func testATitleMatchBeatsAMatchInTheNotes() {
        let notes = ReminderMatch(title: "Einkauf planen", location: "", notes: "Milch kaufen", due: nil)
        let title = ReminderMatch(title: "Milch", location: "", notes: "", due: nil)
        let index = ReminderMatching.bestIndex(in: [notes, title], query: "Milch", now: now, requiresTitle: false)
        XCTAssertEqual(index, 1)
    }

    func testShortWordsAreNotSearchedInsideAFreeText() {
        XCTAssertNil(ReminderMatching.bestIndex(in: [ReminderMatch(title: "Öl", location: "", notes: "", due: nil)],
                                                query: "Öl", now: now, requiresTitle: false))
    }

    func testCompletionRefusesAMatchThatOnlyStandsInTheDetails() {
        let match = ReminderMatch(title: "Einkauf planen", location: "", notes: "Milch kaufen", due: nil)
        XCTAssertNil(ReminderMatching.bestIndex(in: [match], query: "Milch", now: now, requiresTitle: true))
        XCTAssertEqual(ReminderMatching.bestIndex(in: [match], query: "Milch", now: now, requiresTitle: false), 0)
    }

    func testTheNearestDueDateWinsAtEqualStrength() {
        let later = ReminderMatch(title: "Zahnarzt", location: "", notes: "", due: Formatters.eventDate(from: "2026-10-09 09:00"))
        let sooner = ReminderMatch(title: "Zahnarzt", location: "", notes: "", due: Formatters.eventDate(from: "2026-10-08 09:00"))
        XCTAssertEqual(ReminderMatching.bestIndex(in: [later, sooner], query: "Zahnarzt", now: now), 1)
    }

    func testWithoutWordsNothingMatchesAtAll() {
        XCTAssertNil(ReminderMatching.bestIndex(in: [ReminderMatch(title: "Milch", location: "", notes: "", due: nil)],
                                                query: " ", now: now))
    }
}
