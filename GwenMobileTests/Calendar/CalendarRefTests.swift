@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class CalendarRefTests: GwenTestCase {
    private func ref(_ id: String = "ID-1", title: String = "Zahnarzt",
                     start: Date = CalendarRefTests.noontime) -> CalendarRef {
        CalendarRef(eventID: id, title: title, start: start)
    }

    static var noontime: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 24
        components.hour = 14
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    private func decoded(_ json: String) -> ChatMessage? {
        try? JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
    }

    func testTheRoundTripKeepsEveryField() throws {
        let data = try JSONEncoder().encode(ref())
        let back = try JSONDecoder().decode(CalendarRef.self, from: data)
        XCTAssertEqual(back, ref())
        XCTAssertEqual(back.id, "ID-1")
    }

    func testAStoredRefPointsAtItsOwnEventAsItsIdentity() {
        XCTAssertEqual(ref("ANDERS").id, "ANDERS")
    }

    func testAnEmptyIdentifierIsNotOpenable() {
        XCTAssertFalse(ref("").isOpenable)
        XCTAssertTrue(ref().isOpenable)
    }

    func testTheChipNamesTheCalendarDefaultWhenTheTitleIsGone() {
        XCTAssertEqual(ref(title: "").chipTitle, L.t("cal_default_title"))
        XCTAssertEqual(ref(title: " " ).chipTitle, " ")
    }

    func testTheChipStampCarriesTheTimeOfDay() {
        XCTAssertTrue(ref().chipStamp.contains("2:00 PM"), ref().chipStamp)
    }

    func testTheLogSummaryStaysShortEnoughForOneLine() {
        let summary = ref("0123456789abcdef").logSummary
        XCTAssertTrue(summary.contains("Zahnarzt"), summary)
        XCTAssertTrue(summary.contains("01234567"), summary)
        XCTAssertFalse(summary.contains("012345678"), summary)
    }

    func testAMessageWithoutARefStillLoads() throws {
        let legacy = #"{"role":"assistant","text":"✔ Termin angelegt: Zahnarzt"}"#
        let message = try XCTUnwrap(decoded(legacy))
        XCTAssertNil(message.calendarRef)
        XCTAssertEqual(message.text, "✔ Termin angelegt: Zahnarzt")
    }

    func testAMessageCarryingARefLoadsItBack() throws {
        let stored = try JSONEncoder().encode(ChatMessage(role: .assistant, text: "x", calendarRef: ref()))
        let message = try XCTUnwrap(try JSONDecoder().decode(ChatMessage.self, from: stored))
        XCTAssertEqual(message.calendarRef, ref())
    }

    func testAnEmptyRefInsideAMessageDropsOutInsteadOfOpeningNothing() throws {
        let json = #"{"role":"assistant","text":"x","calendarRef":{"eventID":"","title":"Zahnarzt","start":0}}"#
        let message = try XCTUnwrap(decoded(json))
        XCTAssertNil(message.calendarRef)
    }

    func testARefOfTheWrongShapeLeavesTheRestOfTheMessageUsable() throws {
        let json = #"{"role":"assistant","text":"x","calendarRef":"kaputt"}"#
        let message = try XCTUnwrap(decoded(json))
        XCTAssertEqual(message.text, "x")
        XCTAssertNil(message.calendarRef)
    }

    func testHalfDamagedFieldsFallBackWithoutLosingTheIdentifier() throws {
        let json = #"{"role":"assistant","text":"x","calendarRef":{"eventID":"ID-9","title":404,"start":0}}"#
        let message = try XCTUnwrap(decoded(json))
        XCTAssertEqual(message.calendarRef?.eventID, "ID-9")
        XCTAssertEqual(message.calendarRef?.title, "")
    }
}
