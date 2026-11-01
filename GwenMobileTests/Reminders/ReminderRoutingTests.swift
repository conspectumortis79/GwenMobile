@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class ReminderRoutingTests: GwenTestCase {
    private func reminderFunction() throws -> [String: Any] {
        try toolFunction(ToolRouter.reminderTool)
    }

    func testTheReminderToolCarriesTheSameFieldsAsThePlanJson() throws {
        XCTAssertTrue(ToolSchemaNames.of(ToolRouter.tools(attachable: false)).contains(ToolRouter.reminderTool))
        let parameters = try XCTUnwrap(try reminderFunction()["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["required"] as? [String], ["action"])
        let properties = try XCTUnwrap(parameters["properties"] as? [String: Any])
        XCTAssertEqual(properties.keys.sorted(),
                       ["action", "allDay", "due", "find", "list", "location", "minutes", "notes",
                        "priority", "proximity", "repeat", "repeatInterval", "seconds", "title"])
    }

    func testTheReminderDescriptionNamesTheDentistShoppingTimerAndPlace() throws {
        let description = try XCTUnwrap(try reminderFunction()["description"] as? String)
        XCTAssertTrue(description.contains("shopping list"), description)
        XCTAssertTrue(description.contains("timer"), description)
        XCTAssertTrue(description.contains("place triggers"), description)
        XCTAssertTrue(description.contains(ToolRouter.timerTool), description)
        XCTAssertTrue(description.contains(ToolRouter.calendarTool), description)
        XCTAssertTrue(description.contains(ToolRouter.clockTool), description)
    }

    func testTheReminderToolKeepsPlacesOutOfTheListField() throws {
        let parameters = try XCTUnwrap(try reminderFunction()["parameters"] as? [String: Any])
        let properties = try XCTUnwrap(parameters["properties"] as? [String: Any])
        let list = (properties["list"] as? [String: Any])?["description"] as? String
        XCTAssertTrue(list?.contains("A subject, person, shop") ?? false, list ?? "")
        let location = (properties["location"] as? [String: Any])?["description"] as? String
        XCTAssertTrue(location?.contains("kind of place") ?? false, location ?? "")
        XCTAssertTrue(location?.contains("nearest match") ?? false, location ?? "")
    }

    func testTheReminderToolOffersSecondsForShortTimers() throws {
        let parameters = try XCTUnwrap(try reminderFunction()["parameters"] as? [String: Any])
        let properties = try XCTUnwrap(parameters["properties"] as? [String: Any])
        let seconds = (properties["seconds"] as? [String: Any])?["description"] as? String
        XCTAssertTrue(seconds?.contains("under a minute") ?? false, seconds ?? "")
        let description = try XCTUnwrap(try reminderFunction()["description"] as? String)
        XCTAssertTrue(description.contains("timers"), description)
    }

    func testTheReminderToolSeparatesItsNameItsContentAndItsList() throws {
        let parameters = try XCTUnwrap(try reminderFunction()["parameters"] as? [String: Any])
        let properties = try XCTUnwrap(parameters["properties"] as? [String: Any])
        let title = (properties["title"] as? [String: Any])?["description"] as? String
        XCTAssertTrue(title?.contains("never its list") ?? false, title ?? "")
        let notes = (properties["notes"] as? [String: Any])?["description"] as? String
        XCTAssertTrue(notes?.contains("not the title") ?? false, notes ?? "")
        let list = (properties["list"] as? [String: Any])?["description"] as? String
        XCTAssertTrue(list?.contains("is never this list") ?? false, list ?? "")
        XCTAssertTrue(list?.contains("earlier turn") ?? false, list ?? "")
    }

    func testTheCalendarToolNoLongerClaimsReminders() throws {
        let tool = ToolRouter.tools(attachable: false).first {
            ($0["function"] as? [String: Any])?["name"] as? String == ToolRouter.calendarTool
        }
        let description = try XCTUnwrap((tool?["function"] as? [String: Any])?["description"] as? String)
        XCTAssertFalse(description.contains("appointment or reminder"), description)
        XCTAssertTrue(description.contains(ToolRouter.reminderTool), description)
    }

    func testTheClockToolSendsReminderWishesToTheReminderTool() throws {
        let tool = ToolRouter.tools(attachable: false).first {
            ($0["function"] as? [String: Any])?["name"] as? String == ToolRouter.clockTool
        }
        let description = try XCTUnwrap((tool?["function"] as? [String: Any])?["description"] as? String)
        XCTAssertTrue(description.contains(ToolRouter.reminderTool), description)
    }

    func testEveryReminderActionMapsOntoTheReminderRoute() throws {
        let created = try XCTUnwrap(ToolRouter.decisions(
            from: call(ToolRouter.reminderTool,
                       #"{"action":"create","title":"Zahnarzt","due":"2026-10-08 09:00"}"#)).first)
        guard case .reminder(let request) = created.route else {
            return XCTFail("create landete nicht im Reminder-Tool: \(created.route)")
        }
        XCTAssertEqual(request.action, .create)
        XCTAssertEqual(request.title, "Zahnarzt")
        XCTAssertEqual(created.stepKind, .reminder)
        let completed = try XCTUnwrap(ToolRouter.decisions(
            from: call(ToolRouter.reminderTool, #"{"action":"complete","find":"Milch"}"#)).first)
        guard case .reminder(let completeRequest) = completed.route else {
            return XCTFail("complete landete nicht im Reminder-Tool")
        }
        XCTAssertEqual(completeRequest.action, .complete)
        XCTAssertEqual(completeRequest.find, "Milch")
        let listed = try XCTUnwrap(ToolRouter.decisions(
            from: call(ToolRouter.reminderTool, #"{"action":"list","list":"Einkauf"}"#)).first)
        XCTAssertEqual(listed.stepKind, .reminder)
        guard case .reminder(let listRequest) = listed.route else { return XCTFail("list fehlt") }
        XCTAssertEqual(listRequest.action, .list)
        XCTAssertEqual(listRequest.list, "Einkauf")
    }

    func testReminderActionNoneFallsBackToChat() {
        let decision = ToolRouter.decisions(from: call(ToolRouter.reminderTool, #"{"action":"none"}"#)).first
        XCTAssertEqual(decision?.route, .chat)
    }

    func testABrokenReminderCallFallsBackToChat() {
        let decision = ToolRouter.decisions(from: call(ToolRouter.reminderTool, "{action")).first
        XCTAssertEqual(decision?.route, .chat)
    }

    func testTwoThingsOnOneListAreTwoStepsAndDoNotMerge() throws {
        let plan = SendPlan.forming([
            try XCTUnwrap(ToolRouter.map(name: ToolRouter.reminderTool,
                                         arguments: #"{"action":"create","title":"Milch","list":"Einkauf"}"#)),
            try XCTUnwrap(ToolRouter.map(name: ToolRouter.reminderTool,
                                         arguments: #"{"action":"create","title":"Brot","list":"Einkauf"}"#))
        ])
        XCTAssertEqual(plan.traceLine, "reminder+reminder")
        XCTAssertFalse(plan.merges)
        XCTAssertEqual(Set(plan.actions.map(\.stepKey)).count, 2)
    }

    func testThingsAtOnePlaceBecomeOneReminderWithAllOfThemInTheTitle() throws {
        let plan = SendPlan.forming([
            try XCTUnwrap(ToolRouter.map(name: ToolRouter.reminderTool,
                                         arguments: #"{"action":"create","title":"Brot kaufen","location":"Rewe"}"#)),
            try XCTUnwrap(ToolRouter.map(name: ToolRouter.reminderTool,
                                         arguments: #"{"action":"create","title":"Butter kaufen","location":"Rewe"}"#)),
            try XCTUnwrap(ToolRouter.map(name: ToolRouter.reminderTool,
                                         arguments: #"{"action":"create","title":"Kaffee kaufen","location":"Rewe"}"#))
        ])
        XCTAssertEqual(plan.traceLine, "reminder")
        guard case .reminder(let request) = plan.primary.route else {
            return XCTFail("kein Reminder-Schritt: \(plan.traceLine)")
        }
        XCTAssertEqual(request.title, "Brot kaufen, Butter kaufen, Kaffee kaufen")
        XCTAssertEqual(request.place?.name, "Rewe")
    }

    func testThingsAtDifferentPlacesStayTheirOwnReminders() throws {
        let plan = SendPlan.forming([
            try XCTUnwrap(ToolRouter.map(name: ToolRouter.reminderTool,
                                         arguments: #"{"action":"create","title":"Brot kaufen","location":"Rewe"}"#)),
            try XCTUnwrap(ToolRouter.map(name: ToolRouter.reminderTool,
                                         arguments: #"{"action":"create","title":"Paket abholen","location":"Post"}"#))
        ])
        XCTAssertEqual(plan.traceLine, "reminder+reminder")
        XCTAssertFalse(plan.merges)
    }

    func testThingsAtOnePlaceWithDifferentTimesStayTheirOwnReminders() throws {
        let plan = SendPlan.forming([
            try XCTUnwrap(ToolRouter.map(name: ToolRouter.reminderTool,
                                         arguments: #"{"action":"create","title":"Brot kaufen","location":"Rewe","due":"2026-10-05 09:00"}"#)),
            try XCTUnwrap(ToolRouter.map(name: ToolRouter.reminderTool,
                                         arguments: #"{"action":"create","title":"Butter kaufen","location":"Rewe","due":"2026-10-06 09:00"}"#))
        ])
        XCTAssertEqual(plan.traceLine, "reminder+reminder")
    }

    func testOneReminderAndOneAppointmentShareOneAnswer() throws {
        let plan = SendPlan.forming([
            try XCTUnwrap(ToolRouter.map(name: ToolRouter.reminderTool,
                                         arguments: #"{"action":"create","title":"Milch"}"#)),
            try XCTUnwrap(ToolRouter.map(name: ToolRouter.calendarTool,
                                         arguments: #"{"action":"create","title":"Zahnarzt","start":"2026-10-08 09:00"}"#))
        ])
        XCTAssertEqual(plan.traceLine, "reminder+calendar")
        XCTAssertTrue(plan.merges)
    }

    func testTheSplitterKnowsAReminderIsAWishOfItsOwn() {
        let system = WishSplitter.system()
        XCTAssertTrue(system.contains("one item on a shopping list"), system)
        XCTAssertTrue(system.contains("two different things on one shopping list are two wishes"), system)
        XCTAssertTrue(system.contains("A reminder keeps its trigger"), system)
        XCTAssertTrue(system.contains("a place that triggers a reminder stays in that wish"), system)
        XCTAssertTrue(system.contains("also a kind of place"), system)
    }
}
