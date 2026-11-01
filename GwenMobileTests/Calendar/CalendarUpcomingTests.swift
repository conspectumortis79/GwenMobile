@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class CalendarUpcomingTests: GwenTestCase {
    private struct Entry {
        let name: String
        let start: Date
        let end: Date
    }

    private func entry(_ name: String, from now: Date, startHours: Double, lengthHours: Double = 1) -> Entry {
        Entry(name: name,
              start: now.addingTimeInterval(startHours * 3600),
              end: now.addingTimeInterval((startHours + lengthHours) * 3600))
    }

    @MainActor
    func testUpcomingKeepsRunningAndFutureEntriesInOrder() {
        let now = Date()
        let entries = [entry("vorbei", from: now, startHours: -30),
                       entry("spaet", from: now, startHours: 48),
                       entry("laeuft", from: now, startHours: -1, lengthHours: 3),
                       entry("gleich", from: now, startHours: 2)]
        let picked = CalendarService.upcoming(entries, now: now, start: { $0.start }, end: { $0.end })
        XCTAssertEqual(picked.map(\.name), ["laeuft", "gleich", "spaet"])
    }

    @MainActor
    func testTheLimitAppliesToTheNextEntriesNotTheOldestOnes() {
        let now = Date()
        let old = (1...20).map { entry("alt\($0)", from: now, startHours: Double(-$0), lengthHours: 0.25) }
        let next = (1...3).map { entry("neu\($0)", from: now, startHours: Double($0)) }
        let picked = CalendarService.upcoming(old + next, now: now, start: { $0.start }, end: { $0.end }, limit: 3)
        XCTAssertEqual(picked.map(\.name), ["neu1", "neu2", "neu3"])
    }
}
