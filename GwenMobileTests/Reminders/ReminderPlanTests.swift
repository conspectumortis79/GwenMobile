@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class ReminderPlanTests: GwenTestCase {
    private let now = Formatters.eventDate(from: "2026-10-07 15:00")!

    private func plan(_ json: String) throws -> ReminderPlan {
        try JSONDecoder().decode(ReminderPlan.self, from: Data(json.utf8))
    }

    private func makeRequest(_ json: String) throws -> ReminderRequest {
        let decoded = try plan(json)
        return try XCTUnwrap(ReminderRequest(plan: decoded, now: now))
    }

    func testATitleAndDueDateBecomeAReminderRequestAtThatTime() throws {
        let request = try makeRequest(#"{"action":"create","title":"Zahnarzt","due":"2026-10-08 09:00"}"#)
        XCTAssertEqual(request.action, .create)
        XCTAssertEqual(request.title, "Zahnarzt")
        XCTAssertEqual(request.due, Formatters.eventDate(from: "2026-10-08 09:00"))
        XCTAssertFalse(request.allDay)
        XCTAssertNil(request.place)
        XCTAssertNil(request.repeatRule)
    }

    func testATimerCountsMinutesFromNowInsteadOfADueDate() throws {
        let request = try makeRequest(#"{"action":"create","title":"Timer","minutes":10}"#)
        XCTAssertEqual(request.due, now.addingTimeInterval(600))
        XCTAssertFalse(request.allDay)
        XCTAssertEqual(request.minutes, 10)
    }
    func testATimerWithoutATitleBecomesTheTimerWord() throws {
        let request = try makeRequest(#"{"action":"create","minutes":5}"#)
        XCTAssertEqual(request.title, L.t("rem_default_timer"))
        XCTAssertEqual(request.due, now.addingTimeInterval(300))
    }

    func testATimerInSecondsCountsSecondsFromNow() throws {
        let request = try makeRequest(#"{"action":"create","title":"Timer","seconds":10}"#)
        XCTAssertEqual(request.due, now.addingTimeInterval(10))
        XCTAssertEqual(request.seconds, 10)
        XCTAssertFalse(request.allDay)
    }

    func testSecondsBeatMinutesWhenBothArrive() throws {
        let request = try makeRequest(#"{"action":"create","title":"Timer","minutes":5,"seconds":10}"#)
        XCTAssertEqual(request.due, now.addingTimeInterval(10))
    }

    func testACreateWithoutTitleOrMinutesFallsBackToTheReminderWord() throws {
        let request = try makeRequest(#"{"action":"create"}"#)
        XCTAssertEqual(request.title, L.t("rem_default_title"))
        XCTAssertNil(request.due)
    }

    func testADayWithoutATimeStaysAllDay() throws {
        let request = try makeRequest(#"{"action":"create","title":"Reifen","due":"2026-10-08"}"#)
        XCTAssertTrue(request.allDay)
        XCTAssertEqual(request.due, Formatters.eventDay(from: "2026-10-08"))
    }

    func testTheModelMayMarkADayAsAllDayExplicitly() throws {
        let request = try makeRequest(#"{"action":"create","title":"Reifen","due":"2026-10-08 09:00","allDay":true}"#)
        XCTAssertTrue(request.allDay)
    }

    func testRepeatPriorityListAndNotesDecode() throws {
        let request = try makeRequest(#"{"action":"create","title":"Tabletten","due":"2026-10-08 08:00","repeat":"daily","repeatInterval":2,"priority":"high","list":"Gesundheit","notes":"nach dem Frühstück"}"#)
        XCTAssertEqual(request.repeatRule, ReminderRepeat(frequency: .daily, interval: 2))
        XCTAssertEqual(request.priority, .high)
        XCTAssertEqual(request.list, "Gesundheit")
        XCTAssertEqual(request.notes, "nach dem Frühstück")
    }

    func testAnUnknownRepeatWordIsIgnoredInsteadOfGuessed() throws {
        let request = try makeRequest(#"{"action":"create","title":"Yoga","repeat":"mondays"}"#)
        XCTAssertNil(request.repeatRule)
    }

    func testAPlaceAndItsProximityDecode() throws {
        let request = try makeRequest(#"{"action":"create","title":"Milch mitnehmen","location":"REWE","proximity":"arrive"}"#)
        XCTAssertEqual(request.place, ReminderPlace(name: "REWE", proximity: .arrive))
        let leaving = try makeRequest(#"{"action":"create","title":"Schlüssel","location":"Arbeit","proximity":"leave"}"#)
        XCTAssertEqual(leaving.place?.proximity, .leave)
    }

    func testAFindersWishBecomesTheFindWordsForUpdateAndCompletion() throws {
        let complete = try makeRequest(#"{"action":"complete","find":"Milch","list":"Einkauf"}"#)
        XCTAssertEqual(complete.action, .complete)
        XCTAssertEqual(complete.find, "Milch")
        XCTAssertEqual(complete.list, "Einkauf")
        let withTitleOnly = try makeRequest(#"{"action":"delete","title":"Zahnarzt"}"#)
        XCTAssertEqual(withTitleOnly.find, "Zahnarzt")
    }

    func testActionNoneBuildsNoRequest() throws {
        let decoded = try plan(#"{"action":"none"}"#)
        XCTAssertNil(ReminderRequest(plan: decoded, now: now))
    }

    func testTheWholePlanFillsWhatThePerWishReminderLeavesOpen() throws {
        let whole = try makeRequest(#"{"action":"create","title":"Milch","find":"Milch","due":"2026-10-08 09:00","list":"Einkauf","location":"REWE","notes":"kalt","priority":"high","repeat":"daily","repeatInterval":2,"minutes":5,"seconds":10}"#)
        let routed = try makeRequest(#"{"action":"create"}"#)
        XCTAssertEqual(ReminderMerge.merged(routed, with: whole), whole)
    }

    func testThePerWishReminderKeepsItsOwnValues() throws {
        let routed = try makeRequest(#"{"action":"create","title":"Brot","find":"Brot kaufen","due":"2026-10-09 10:00","list":"Einkauf","location":"Bäckerei","notes":"frisch","priority":"low","repeat":"weekly","repeatInterval":1,"minutes":3,"seconds":20}"#)
        let whole = try makeRequest(#"{"action":"create","title":"Milch","find":"Milch","due":"2026-10-08 09:00","list":"Andere","location":"REWE","notes":"kalt","priority":"high","repeat":"daily","repeatInterval":2,"minutes":5,"seconds":10}"#)
        XCTAssertEqual(ReminderMerge.merged(routed, with: whole), routed)
    }

    func testStepWordsCarryActionTitleListAndPlace() throws {
        let request = try makeRequest(#"{"action":"create","title":"Milch","list":"Einkauf","location":"REWE"}"#)
        XCTAssertTrue(request.stepWords.contains("create"))
        XCTAssertTrue(request.stepWords.contains("Milch"))
        XCTAssertTrue(request.stepWords.contains("Einkauf"))
        XCTAssertTrue(request.stepWords.contains("REWE"))
    }
}
