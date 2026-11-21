@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class AppointmentReminderTests: GwenTestCase {
    private func map(_ tool: String, _ json: String, wish: String? = nil) throws -> ToolDecision {
        var decision = try XCTUnwrap(ToolRouter.map(name: tool, arguments: json))
        if let wish { decision.wish = wish }
        return decision
    }

    private func reminderDecision(_ json: String = #"{"action":"create","title":"Zahnarzt"}"#,
                                  wish: String? = nil) throws -> ToolDecision {
        try map(ToolRouter.reminderTool, json, wish: wish)
    }

    private func calendarDecision(_ json: String =
                                  #"{"action":"create","title":"Zahnarzt","start":"2026-10-08 11:00"}"#,
                                  wish: String? = nil) throws -> ToolDecision {
        try map(ToolRouter.calendarTool, json, wish: wish)
    }

    func testOneWishAnsweredWithBothNeedsReconciliation() throws {
        let decisions = [try reminderDecision(), try calendarDecision()]
        XCTAssertEqual(AppointmentReminderCheck.groups(in: decisions), [[0, 1]])
    }

    func testBothKindsWithoutAWishAreOneGroupToo() throws {
        let decisions = [try calendarDecision(), try reminderDecision()]
        XCTAssertEqual(AppointmentReminderCheck.groups(in: decisions), [[0, 1]])
    }

    func testTwoSeparateWishesStayUntouched() throws {
        let decisions = [try reminderDecision(wish: "Erinnere mich an den Zahnarzt"),
                         try calendarDecision(wish: "Trag einen Termin um 11 Uhr ein")]
        XCTAssertTrue(AppointmentReminderCheck.groups(in: decisions).isEmpty)
    }

    func testOneKindAloneNeedsNoCheck() throws {
        XCTAssertTrue(AppointmentReminderCheck.groups(in: [try calendarDecision()]).isEmpty)
        XCTAssertTrue(AppointmentReminderCheck.groups(in: [try reminderDecision(), try reminderDecision()]).isEmpty)
    }

    func testTheSameWishSplitApartByAnotherWishIsNotCollapsed() async throws {
        let decisions = [try reminderDecision(wish: "Zahnarzt"),
                         try reminderDecision(wish: "Milch"),
                         try calendarDecision(wish: "Zahnarzt")]
        XCTAssertTrue(AppointmentReminderCheck.groups(in: decisions).isEmpty)
        let reconciled = await AppointmentReminderCheck.reconciled(decisions, message: "x") { _, _ in nil }
        XCTAssertEqual(reconciled.map(\.stepKind), decisions.map(\.stepKind))
    }

    func testTwoAdjacentRunsAreEachReconciledOnTheirOwn() async throws {
        let decisions = [try reminderDecision(wish: "Zahnarzt"), try calendarDecision(wish: "Zahnarzt"),
                         try reminderDecision(wish: "Milch"), try calendarDecision(wish: "Milch")]
        XCTAssertEqual(AppointmentReminderCheck.groups(in: decisions), [[0, 1], [2, 3]])
        let fresh = try calendarDecision(wish: "Zahnarzt")
        let reconciled = await AppointmentReminderCheck.reconciled(decisions, message: "x") { _, _ in [fresh] }
        XCTAssertEqual(reconciled.map(\.stepKind), [.calendar, .calendar])
    }

    func testAnAppointmentAndItsNotificationSplitIntoTwoWishesAreReconciled() async throws {
        let calendar = try calendarDecision(
            #"{"action":"create","title":"Testtermin","start":"2026-11-15 11:00","end":"2026-11-15 12:00"}"#,
            wish: "für morgen einen Termin von elf bis 12:00 Uhr mit dem Namen Testtermin")
        let reminder = try reminderDecision(
            #"{"action":"create","title":"Testtermin","due":"2026-11-15 10:30","notes":"Testnotiz"}"#,
            wish: "30 Minuten vor dem Termin Testtermin ein Hinweis mit der Notiz Testnotiz")
        XCTAssertEqual(AppointmentReminderCheck.groups(in: [calendar, reminder]), [[0, 1]])
        var fresh = calendar
        fresh.calendarPlan?.alerts = [30]
        fresh.calendarPlan?.notes = "Testnotiz"
        var asked = ""
        let reconciled = await AppointmentReminderCheck.reconciled([calendar, reminder], message: "x") {
            wish, _ in
            asked = wish
            return [fresh]
        }
        XCTAssertEqual(asked, calendar.wishText + "\n" + reminder.wishText)
        XCTAssertEqual(reconciled.map(\.stepKind), [.calendar])
        XCTAssertEqual(reconciled.first?.calendarPlan?.alerts, [30])
        XCTAssertEqual(reconciled.first?.calendarPlan?.notes, "Testnotiz")
        XCTAssertEqual(reconciled.first?.wish, asked)
    }

    func testAnAppointmentAndAnUnrelatedReminderStaySeparate() async throws {
        let calendar = try calendarDecision(
            #"{"action":"create","title":"Testtermin","start":"2026-11-15 11:00","end":"2026-11-15 12:00"}"#,
            wish: "Termin Testtermin")
        let otherTitle = try reminderDecision(
            #"{"action":"create","title":"Einkaufen","due":"2026-11-15 10:30"}"#,
            wish: "Erinnere mich an Einkaufen")
        let afterStart = try reminderDecision(
            #"{"action":"create","title":"Testtermin","due":"2026-11-15 11:30"}"#,
            wish: "Erinnere mich an Testtermin")
        let noDue = try reminderDecision(#"{"action":"create","title":"Testtermin"}"#,
                                         wish: "Erinnere mich an Testtermin")
        XCTAssertTrue(AppointmentReminderCheck.groups(in: [calendar, otherTitle]).isEmpty)
        XCTAssertTrue(AppointmentReminderCheck.groups(in: [calendar, afterStart]).isEmpty)
        XCTAssertTrue(AppointmentReminderCheck.groups(in: [calendar, noDue]).isEmpty)
    }

    func testTheReplacementKeepsTheWishOfItsRun() async throws {
        let decisions = [try reminderDecision(wish: "Zahnarzt morgen"), try calendarDecision(wish: "Zahnarzt morgen"),
                         try reminderDecision(wish: "Milch kaufen")]
        let fresh = try calendarDecision()
        var asked: [String] = []
        let reconciled = await AppointmentReminderCheck.reconciled(decisions, message: "ganze Nachricht") { wish, _ in
            asked.append(wish)
            return [fresh]
        }
        XCTAssertEqual(asked, ["Zahnarzt morgen"])
        XCTAssertEqual(reconciled.map(\.wish), ["Zahnarzt morgen", "Milch kaufen"])
        let whole = [try reminderDecision(), try calendarDecision()]
        let unnamed = await AppointmentReminderCheck.reconciled(whole, message: "ganze Nachricht") { wish, _ in
            XCTAssertEqual(wish, "ganze Nachricht")
            return [fresh]
        }
        XCTAssertEqual(unnamed.map(\.wish), [nil])
    }

    func testTheModelKeepsOnlyTheCallTheWordsAskFor() async throws {
        let decisions = [try reminderDecision(), try calendarDecision()]
        let calendarOnly = try calendarDecision()
        let reconciled = await AppointmentReminderCheck.reconciled(decisions, message: "Termin") { _, hint in
            XCTAssertTrue(hint.contains("appointment"))
            XCTAssertTrue(hint.contains("reminder"))
            XCTAssertTrue(hint.contains("alerts"))
            return [calendarOnly]
        }
        XCTAssertEqual(reconciled.map(\.stepKind), [.calendar])
        XCTAssertEqual(reconciled.first?.calendarPlan?.action, .create)
    }

    func testTheReminderWinsWhenTheWordsAskForAReminder() async throws {
        let decisions = [try calendarDecision(), try reminderDecision()]
        let reminderOnly = try reminderDecision()
        let reconciled = await AppointmentReminderCheck.reconciled(decisions, message: "Erinnerung") { _, _ in
            [reminderOnly]
        }
        XCTAssertEqual(reconciled.map(\.stepKind), [.reminder])
    }

    func testAnUnreachableReaskKeepsTheOriginalCalls() async throws {
        let decisions = [try reminderDecision(), try calendarDecision()]
        let reconciled = await AppointmentReminderCheck.reconciled(decisions, message: "Termin") { _, _ in nil }
        XCTAssertEqual(reconciled.map(\.stepKind), decisions.map(\.stepKind))
    }

    func testAModelThatInsistsOnBothKeepsBoth() async throws {
        let decisions = [try reminderDecision(), try calendarDecision()]
        let reconciled = await AppointmentReminderCheck.reconciled(decisions, message: "Termin und Erinnerung") {
            _, _ in decisions
        }
        XCTAssertEqual(reconciled.map(\.stepKind), [.reminder, .calendar])
    }

    func testTheReconciledCallKeepsItsPlaceInThePlan() async throws {
        let chat = ToolDecision(route: .chat)
        let reminder = try reminderDecision(wish: "Zahnarzt")
        let calendar = try calendarDecision(wish: "Zahnarzt")
        let calendarOnly = try calendarDecision(wish: "Zahnarzt")
        let reconciled = await AppointmentReminderCheck.reconciled([chat, reminder, calendar], message: "x") {
            _, _ in [calendarOnly]
        }
        XCTAssertEqual(reconciled.count, 2)
        XCTAssertEqual(reconciled.map(\.stepKind), [.chat, .calendar])
    }
}
