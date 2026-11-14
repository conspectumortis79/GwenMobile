@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class CalendarChoiceTests: XCTestCase {

    private let calendars = ["Arbeit", "Privat", "Zu Hause"]

    private func resolve(_ requested: String?, available: [String]? = nil,
                         deviceDefault: String?, silent: CalendarChoice.Silent = .deviceDefault)
        -> CalendarChoice.Outcome {
        CalendarChoice.resolve(requested: requested, available: available ?? calendars,
                              deviceDefault: deviceDefault, silent: silent)
    }

    func testSilentCreateTakesTheDeviceDefaultCalendar() {
        XCTAssertEqual(resolve(nil, deviceDefault: "Privat"), .title("Privat"))
        XCTAssertEqual(resolve("   ", deviceDefault: "Zu Hause"), .title("Zu Hause"))
    }

    func testSilentCreateWithoutAUsableDeviceDefaultTakesTheFirstWritableCalendar() {
        XCTAssertEqual(resolve(nil, available: ["Privat", "Sonstiges"], deviceDefault: "Intern"),
                       .title("Privat"))
        XCTAssertEqual(resolve(nil, available: ["Privat", "Sonstiges"], deviceDefault: nil), .title("Privat"))
    }

    func testSilentUpdateKeepsTheCurrentCalendar() {
        XCTAssertEqual(resolve(nil, deviceDefault: "Arbeit", silent: .keepCurrent), .keep)
    }

    func testWithoutAnyCalendarNothingIsChanged() {
        XCTAssertEqual(resolve(nil, available: [], deviceDefault: nil), .keep)
    }

    func testATitleMatchesRegardlessOfCaseAndAccents() {
        XCTAssertEqual(resolve("PRIVAT", deviceDefault: "Arbeit"), .title("Privat"))
        XCTAssertEqual(resolve("persönlich", available: ["Arbeit", "Persönlich"], deviceDefault: "Arbeit"),
                       .title("Persönlich"))
    }

    func testATitleInsideASentenceIsEnough() {
        XCTAssertEqual(resolve("Bitte den Kalender auf privat setzen", deviceDefault: "Arbeit"),
                       .title("Privat"))
    }

    func testOnlyWhatTheDeviceReallyNamesCanMatch() {
        XCTAssertEqual(resolve("private", deviceDefault: "Arbeit"), .title("Privat"),
                       "„private“ enthält den Gerätenamen „Privat“ - das ist Titelvergleich, kein Synonym")
        XCTAssertEqual(resolve("work", deviceDefault: "Privat"), .unmatched("work"),
                       "ein englisches Synonym für „Arbeit“ ist kein Gerätekalender")
        XCTAssertEqual(resolve("Family", deviceDefault: "Arbeit"), .unmatched("Family"))
    }

    func testTitleWithSpacesMatchesARequestWithoutThem() {
        XCTAssertEqual(resolve("zuhause", deviceDefault: "Arbeit"), .title("Zu Hause"))
    }

    func testTheExactTitleBeatsALongerMention() {
        XCTAssertEqual(resolve("Privat Termine",
                               available: ["Privat", "Privat Termine", "Arbeit"], deviceDefault: "Arbeit"),
                       .title("Privat Termine"))
        XCTAssertEqual(resolve("privat", available: ["Privat Termine", "Privat"], deviceDefault: "Arbeit"),
                       .title("Privat"))
    }

    func testQuotedTitleStillMatches() {
        XCTAssertEqual(resolve("„Arbeit“", deviceDefault: "Privat"), .title("Arbeit"))
    }

    func testUnknownCalendarIsReportedInsteadOfGuessing() {
        XCTAssertEqual(resolve("Kegelclub", deviceDefault: "Arbeit"), .unmatched("Kegelclub"))
    }

    func testShortCalendarNamesAreNotSearchedInsideLongWords() {
        XCTAssertEqual(resolve("Arbeit", available: ["A", "Büro"], deviceDefault: nil,
                               silent: .keepCurrent), .unmatched("Arbeit"))
        XCTAssertEqual(resolve("Mein Projekt", available: ["M", "Projekt"], deviceDefault: nil,
                               silent: .keepCurrent), .title("Projekt"))
    }

    func testShortTitleWordsAreNotSearchedInsideFreeText() {
        XCTAssertEqual(resolve("ich und du", available: ["ich", "du"], deviceDefault: nil,
                               silent: .keepCurrent), .unmatched("ich und du"),
                       "zwei-KBuchstaben-Namen dürfen nicht jeden Satz treffen")
        XCTAssertEqual(resolve("du", available: ["du"], deviceDefault: nil, silent: .keepCurrent), .title("du"),
                       "genau so geschrieben darf der Name aber getroffen werden")
    }

    func testMissingCalendarMessageListsWhatExists() {
        L.apply(.de)
        XCTAssertEqual(L.fmt2("cal_calendar_missing", "Kegelclub", "Arbeit, Privat"),
                       "Einen Kalender \"Kegelclub\" gibt es nicht — zur Auswahl: Arbeit, Privat")
    }

    func testCalendarPlanDecodesTheCalendarField() throws {
        let json = #"{"action":"update","find":"Zahnarzt","calendar":"Privat"}"#
        let plan = try JSONDecoder().decode(QwenAPI.CalendarPlan.self, from: Data(json.utf8))
        XCTAssertEqual(plan.action, .update)
        XCTAssertEqual(plan.find, "Zahnarzt")
        XCTAssertEqual(plan.calendar, "Privat")
    }

    func testCalendarPlanWithoutACalendarFieldStaysSilent() throws {
        let json = #"{"action":"create","title":"Zahnarzt","start":"2026-09-12 14:00"}"#
        let plan = try JSONDecoder().decode(QwenAPI.CalendarPlan.self, from: Data(json.utf8))
        XCTAssertNil(plan.calendar)
    }

    func testTheSharedFoldingIsWhatTitlesAreComparedWith() {
        XCTAssertEqual(TextFolding.fold("Grün  —   „Notiz“"), "grun — notiz")
        XCTAssertEqual(CalendarChoice.normalize("Grün"), TextFolding.fold("Grün"))
    }
}
