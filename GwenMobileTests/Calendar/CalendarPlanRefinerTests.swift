@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class CalendarPlanRefinerTests: XCTestCase {

    func testThePlannerMayFillFieldsButNeverChangeACreateIntoAnUpdate() throws {
        var routed = QwenAPI.CalendarPlan(action: .create)
        routed.title = "GwenErst"
        var planner = QwenAPI.CalendarPlan(action: .update)
        planner.find = "GwenErst"
        planner.start = "2026-09-30 10:00"
        let kept = try XCTUnwrap(CalendarPlanRefiner.keepAction(routed, filledBy: planner, targetExists: false))
        XCTAssertEqual(kept.action, .create, "das Werkzeug hat entschieden: anlegen")
        XCTAssertNil(kept.find, "ein Anlegen sucht kein bestehendes Ereignis")
        XCTAssertEqual(kept.start, "2026-09-30 10:00", "Datum und Uhrzeit bleiben aus dem Planer")
        XCTAssertEqual(kept.title, "GwenErst", "ohne Planer-Titel gilt der Titel des Werkzeugs")
    }

    func testAPlannerThatFoundNothingLeftKeepsTheRoutedCreate() throws {
        var routed = QwenAPI.CalendarPlan(action: .create)
        routed.title = "Banane"
        routed.start = "2026-09-30 11:00"
        let empty = QwenAPI.CalendarPlan(action: .none)
        let kept = try XCTUnwrap(CalendarPlanRefiner.keepAction(routed, filledBy: empty, targetExists: false))
        XCTAssertEqual(kept.action, .create)
        XCTAssertEqual(kept.title, "Banane")
        XCTAssertEqual(kept.start, "2026-09-30 11:00")
    }

    func testAPlannerThatAgreesOnCreateIsTakenAsIs() throws {
        var routed = QwenAPI.CalendarPlan(action: .create)
        routed.title = "Termin"
        var planner = QwenAPI.CalendarPlan(action: .create)
        planner.title = "Banane"
        planner.start = "2026-10-01 09:00"
        let kept = try XCTUnwrap(CalendarPlanRefiner.keepAction(routed, filledBy: planner, targetExists: false))
        XCTAssertEqual(kept.title, "Banane")
        XCTAssertEqual(kept.start, "2026-10-01 09:00")
    }

    func testAnUpdateStaysAnUpdateWhenThePlannerAgrees() throws {
        var routed = QwenAPI.CalendarPlan(action: .update)
        routed.find = "Zahnarzt"
        var planner = QwenAPI.CalendarPlan(action: .update)
        planner.find = "Zahnarzt"
        planner.start = "2026-10-02 15:00"
        let kept = try XCTUnwrap(CalendarPlanRefiner.keepAction(routed, filledBy: planner, targetExists: false))
        XCTAssertEqual(kept.action, .update)
        XCTAssertEqual(kept.start, "2026-10-02 15:00")
    }

    func testAnUpdateThePlannerMakesIsKeptWhenTheTargetReallyExists() throws {
        var routed = QwenAPI.CalendarPlan(action: .create)
        routed.title = "GwenErst"
        var planner = QwenAPI.CalendarPlan(action: .update)
        planner.find = "GwenErst"
        planner.start = "2026-09-30 10:00"
        let kept = try XCTUnwrap(CalendarPlanRefiner.keepAction(routed, filledBy: planner,
                                                                targetExists: true))
        XCTAssertEqual(kept.action, .update, "gibt es das Ereignis, ist Ändern der richtige Auftrag")
        XCTAssertEqual(kept.find, "GwenErst")
    }

    func testDifferentAppointmentNamesAreNotDuplicates() {
        XCTAssertFalse(CalendarPlanRefiner.sameAppointment("Zahnarzt", "Zahnarzt Kontrolle"))
        XCTAssertFalse(CalendarPlanRefiner.sameAppointment("Termin", "Termin mit Arzt"))
    }

    func testAppointmentNamesAreComparedWithoutSpacesOrCase() {
        XCTAssertTrue(CalendarPlanRefiner.sameAppointment("Gwen Kurz", "gwenkurz"))
        XCTAssertTrue(CalendarPlanRefiner.sameAppointment("GwenErst", "Gwen Erst"))
        XCTAssertFalse(CalendarPlanRefiner.sameAppointment("GwenErst", "Zahnarzt"))
        XCTAssertFalse(CalendarPlanRefiner.sameAppointment("GwenErst", "  "),
                       "leere Wörter sind kein Treffer, sonst wäre jede Anlage ein Duplikat")
    }

}
