import XCTest
@testable import GwenMobile

final class CalendarChoiceTests: XCTestCase {

    private let calendars = ["Arbeit", "Privat", "Zu Hause"]

    func testSilentCreateFallsIntoTheWorkCalendar() {
        let outcome = CalendarChoice.resolve(requested: nil, available: calendars,
                                             deviceDefault: "Privat", silent: .preferWork)
        XCTAssertEqual(outcome, .title("Arbeit"))
    }

    func testBlankRequestCountsAsSilent() {
        let outcome = CalendarChoice.resolve(requested: "   ", available: calendars,
                                             deviceDefault: "Privat", silent: .preferWork)
        XCTAssertEqual(outcome, .title("Arbeit"))
    }

    func testSilentCreateWithoutWorkCalendarUsesTheDeviceDefault() {
        let outcome = CalendarChoice.resolve(requested: nil, available: ["Privat", "Sonstiges"],
                                             deviceDefault: "Privat", silent: .preferWork)
        XCTAssertEqual(outcome, .title("Privat"))
    }

    func testSilentCreateWithoutDeviceDefaultTakesTheFirstWritableCalendar() {
        let outcome = CalendarChoice.resolve(requested: nil, available: ["Privat", "Sonstiges"],
                                             deviceDefault: nil, silent: .preferWork)
        XCTAssertEqual(outcome, .title("Privat"))
    }

    func testSilentUpdateKeepsTheCurrentCalendar() {
        let outcome = CalendarChoice.resolve(requested: nil, available: calendars,
                                             deviceDefault: "Arbeit", silent: .keepCurrent)
        XCTAssertEqual(outcome, .keep)
    }

    func testWithoutAnyCalendarNothingIsChanged() {
        let outcome = CalendarChoice.resolve(requested: nil, available: [],
                                             deviceDefault: nil, silent: .preferWork)
        XCTAssertEqual(outcome, .keep)
    }

    func testPrivateKeywordIsCaseInsensitive() {
        let outcome = CalendarChoice.resolve(requested: "PRIVAT", available: calendars,
                                             deviceDefault: "Arbeit", silent: .preferWork)
        XCTAssertEqual(outcome, .title("Privat"))
    }

    func testPrivateKeywordInsideASentenceIsEnough() {
        let outcome = CalendarChoice.resolve(requested: "Bitte den Kalender auf privat setzen",
                                             available: calendars, deviceDefault: "Arbeit",
                                             silent: .preferWork)
        XCTAssertEqual(outcome, .title("Privat"))
    }

    func testEnglishWordSelectsTheGermanPrivateCalendar() {
        let outcome = CalendarChoice.resolve(requested: "private", available: calendars,
                                             deviceDefault: "Arbeit", silent: .preferWork)
        XCTAssertEqual(outcome, .title("Privat"))
    }

    func testWorkWordSelectsTheWorkCalendar() {
        let outcome = CalendarChoice.resolve(requested: "work", available: calendars,
                                             deviceDefault: "Privat", silent: .preferWork)
        XCTAssertEqual(outcome, .title("Arbeit"))
    }

    func testUmlautTitlesMatchIgnoringAccents() {
        let outcome = CalendarChoice.resolve(requested: "persönlich", available: ["Arbeit", "Persönlich"],
                                             deviceDefault: "Arbeit", silent: .preferWork)
        XCTAssertEqual(outcome, .title("Persönlich"))
    }

    func testTitleWithSpacesMatchesARequestWithoutThem() {
        let outcome = CalendarChoice.resolve(requested: "zuhause", available: calendars,
                                             deviceDefault: "Arbeit", silent: .preferWork)
        XCTAssertEqual(outcome, .title("Zu Hause"))
    }

    func testExactTitleBeatsTheKeywordCategory() {
        let outcome = CalendarChoice.resolve(requested: "Privat Termine",
                                             available: ["Privat", "Privat Termine", "Arbeit"],
                                             deviceDefault: "Arbeit", silent: .preferWork)
        XCTAssertEqual(outcome, .title("Privat Termine"))
    }

    func testQuotedTitleStillMatches() {
        let outcome = CalendarChoice.resolve(requested: "„Arbeit“", available: calendars,
                                             deviceDefault: "Privat", silent: .preferWork)
        XCTAssertEqual(outcome, .title("Arbeit"))
    }

    func testExactHintMatchWinsOverALongerTitle() {
        let outcome = CalendarChoice.resolve(requested: "privat",
                                             available: ["Privat Termine", "Privat"],
                                             deviceDefault: "Arbeit", silent: .preferWork)
        XCTAssertEqual(outcome, .title("Privat"))
    }

    func testUnknownCalendarIsReportedInsteadOfGuessing() {
        let outcome = CalendarChoice.resolve(requested: "Kegelclub", available: calendars,
                                             deviceDefault: "Arbeit", silent: .preferWork)
        XCTAssertEqual(outcome, .unmatched("Kegelclub"))
    }

    func testWorkKeywordWithoutAWorkCalendarIsUnmatched() {
        let outcome = CalendarChoice.resolve(requested: "arbeit", available: ["Privat", "Google"],
                                             deviceDefault: "Privat", silent: .preferWork)
        XCTAssertEqual(outcome, .unmatched("arbeit"))
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
}
