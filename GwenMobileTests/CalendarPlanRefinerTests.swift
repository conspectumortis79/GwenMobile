import XCTest
@testable import GwenMobile

final class CalendarPlanRefinerTests: XCTestCase {

    private func madePlan(action: QwenAPI.CalendarPlan.Action = .update,
                          title: String? = nil,
                          notes: String? = nil,
                          find: String? = nil,
                          calendar: String? = nil) -> QwenAPI.CalendarPlan {
        QwenAPI.CalendarPlan(action: action, title: title, start: nil, end: nil,
                             location: nil, notes: notes, find: find, alerts: nil, calendar: calendar)
    }

    func testCalendarHintThatArrivedAsNoteBecomesACalendarPick() {
        let refined = CalendarPlanRefiner.refine(madePlan(notes: "privat", find: "Banana"),
                                                 instruction: "banana termin morgen um 14 uhr")
        XCTAssertEqual(refined.calendar, "privat")
        XCTAssertNil(refined.notes)
        XCTAssertEqual(refined.find, "Banana")
    }

    func testFollowUpThatOnlyNamesACalendarIsTakenFromTheInstruction() {
        let refined = CalendarPlanRefiner.refine(madePlan(notes: "privat statt arbeit", find: "Banana"),
                                                 instruction: "bitte privat statt arbeit")
        XCTAssertEqual(refined.calendar, "privat")
        XCTAssertNil(refined.notes)
    }

    func testWorkBeforePrivateMeansWork() {
        let refined = CalendarPlanRefiner.refine(madePlan(find: "Banana"),
                                                 instruction: "also doch arbeit statt privat")
        XCTAssertEqual(refined.calendar, "arbeit")
    }

    func testTheModelAnswerWinsOverTheInstruction() {
        let refined = CalendarPlanRefiner.refine(madePlan(find: "Banana", calendar: "Privat"),
                                                 instruction: "arbeit")
        XCTAssertEqual(refined.calendar, "Privat")
    }

    func testBlankCalendarFromTheModelCountsAsNoAnswer() {
        let refined = CalendarPlanRefiner.refine(madePlan(find: "Banana", calendar: "   "),
                                                 instruction: "bitte privat")
        XCTAssertEqual(refined.calendar, "privat")
    }

    func testRealNotesStayUntouched() {
        let refined = CalendarPlanRefiner.refine(madePlan(notes: "Betablocker 5mg", find: "Banana"),
                                                 instruction: "mach den termin privat")
        XCTAssertEqual(refined.notes, "Betablocker 5mg")
        XCTAssertEqual(refined.calendar, "privat")
    }

    func testInstructionWithoutACalendarWordChangesNothing() {
        let refined = CalendarPlanRefiner.refine(madePlan(notes: "Zahnpflege", find: "Banana"),
                                                 instruction: "morgen um 14 uhr")
        XCTAssertNil(refined.calendar)
        XCTAssertEqual(refined.notes, "Zahnpflege")
    }

    func testEnglishHintIsRecognised() {
        XCTAssertEqual(CalendarPlanRefiner.category(in: "please keep it private"), "privat")
        XCTAssertEqual(CalendarPlanRefiner.category(in: "book it in work"), "arbeit")
        XCTAssertNil(CalendarPlanRefiner.category(in: "morgen 14 uhr"))
    }

    func testPureCalendarHintDetection() {
        XCTAssertTrue(CalendarPlanRefiner.isPureCalendarHint("privat"))
        XCTAssertTrue(CalendarPlanRefiner.isPureCalendarHint("Bitte nur als Notiz privat"))
        XCTAssertTrue(CalendarPlanRefiner.isPureCalendarHint("Private"))
        XCTAssertTrue(CalendarPlanRefiner.isPureCalendarHint("Persönlich"))
        XCTAssertFalse(CalendarPlanRefiner.isPureCalendarHint("Kunde privat"))
        XCTAssertFalse(CalendarPlanRefiner.isPureCalendarHint("Praxis Am Markt"))
        XCTAssertFalse(CalendarPlanRefiner.isPureCalendarHint(""))
        XCTAssertFalse(CalendarPlanRefiner.isPureCalendarHint("privater Termin mit der Familie am Wochenende"))
    }
}
