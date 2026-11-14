@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit
@testable import GwenMobileProbes

@MainActor
private struct FixedPlaceLookup: ReminderPlaceLooking {
    var points: [String: GeoPoint] = [:]

    func locate(_ name: String) async -> GeoPoint? { points[name] }
}

@MainActor
final class ReminderFlowRunnerTests: GwenTestCase {
    private func request(_ json: String) throws -> ReminderRequest {
        let plan = try JSONDecoder().decode(ReminderPlan.self, from: Data(json.utf8))
        return try XCTUnwrap(ReminderRequest(plan: plan))
    }

    private func run(_ json: String, _ store: ProbeReminderStore,
                     _ places: FixedPlaceLookup = FixedPlaceLookup()) async throws -> ReminderFlowOutcome {
        let parsed = try request(json)
        return await ReminderFlowRunner(store: store, places: places).run(parsed)
    }

    private func seed(_ store: ProbeReminderStore, _ reminder: StoredReminder) {
        store.stored.append(reminder)
    }

    func testACreateGoesToTheDefaultList() async throws {
        let store = ProbeReminderStore()
        let outcome = try await run(#"{"action":"create","title":"Zahnarzt","due":"2026-10-08 09:00"}"#, store)
        XCTAssertEqual(store.stored.count, 1)
        XCTAssertEqual(store.stored[0].list, "Erinnerungen")
        XCTAssertEqual(store.stored[0].due, Formatters.eventDate(from: "2026-10-08 09:00"))
        XCTAssertTrue(outcome.text.contains("Zahnarzt"), outcome.text)
        XCTAssertEqual(outcome.ref?.title, "Zahnarzt")
    }

    func testAShoppingItemGoesToTheNamedList() async throws {
        let store = ProbeReminderStore()
        _ = try await run(#"{"action":"create","title":"Milch","list":"Einkauf"}"#, store)
        XCTAssertEqual(store.stored.map(\.list), ["Einkauf"])
    }

    func testAnUnknownListIsReportedInsteadOfGuessed() async throws {
        let store = ProbeReminderStore()
        let outcome = try await run(#"{"action":"create","title":"Milch","list":"Kühlschrank"}"#, store)
        XCTAssertTrue(store.stored.isEmpty)
        XCTAssertTrue(outcome.text.contains("Kühlschrank"), outcome.text)
        XCTAssertTrue(outcome.text.contains("Einkauf"), outcome.text)
    }

    func testATimerIsDueInItsMinutes() async throws {
        let store = ProbeReminderStore()
        _ = try await run(#"{"action":"create","minutes":10,"title":"Timer"}"#, store)
        let due = try XCTUnwrap(store.stored.first?.due)
        XCTAssertEqual(due.timeIntervalSinceNow, 600, accuracy: 5)
        XCTAssertEqual(store.stored.first?.title, "Timer")
    }

    func testASecondsTimerIsDueInItsSeconds() async throws {
        let store = ProbeReminderStore()
        _ = try await run(#"{"action":"create","seconds":10,"title":"Timer"}"#, store)
        let due = try XCTUnwrap(store.stored.first?.due)
        XCTAssertEqual(due.timeIntervalSinceNow, 10, accuracy: 5)
        XCTAssertEqual(store.stored.first?.title, "Timer")
    }

    func testAPlaceWishGetsItsCoordinatesForTheLocationAlarm() async throws {
        let store = ProbeReminderStore()
        let point = GeoPoint(latitude: 52.5, longitude: 13.4, radius: 150)
        let outcome = try await run(#"{"action":"create","title":"Milch mitnehmen","location":"REWE"}"#,
                                    store, FixedPlaceLookup(points: ["REWE": point]))
        XCTAssertEqual(store.stored.first?.place, "REWE")
        XCTAssertEqual(store.stored.first?.proximity, .arrive)
        XCTAssertEqual(store.coordinates[store.stored.first?.id ?? ""], point)
        XCTAssertTrue(outcome.text.contains("Milch mitnehmen"), outcome.text)
    }

    func testALeavingWishKeepsItsProximity() async throws {
        let store = ProbeReminderStore()
        let point = GeoPoint(latitude: 48.1, longitude: 11.5, radius: 150)
        _ = try await run(#"{"action":"create","title":"Schlüssel","location":"Arbeit","proximity":"leave"}"#,
                          store, FixedPlaceLookup(points: ["Arbeit": point]))
        XCTAssertEqual(store.stored.first?.proximity, .leave)
    }

    func testAPlaceThatCannotBeFoundLeavesNothingBehind() async throws {
        let store = ProbeReminderStore()
        let outcome = try await run(#"{"action":"create","title":"Milch","location":"Nirgendwo"}"#, store)
        XCTAssertTrue(store.stored.isEmpty)
        XCTAssertTrue(outcome.text.contains("Nirgendwo"), outcome.text)
    }

    func testCompletingFindsTheReminderByItsTitle() async throws {
        let store = ProbeReminderStore()
        seed(store, StoredReminder(id: "r1", title: "Milch", list: "Einkauf"))
        let outcome = try await run(#"{"action":"complete","find":"Milch","list":"Einkauf"}"#, store)
        XCTAssertEqual(store.stored.first?.isCompleted, true)
        XCTAssertTrue(outcome.text.contains("Milch"), outcome.text)
        XCTAssertEqual(outcome.ref?.reminderID, "r1")
    }

    func testAPlaceInTheNotesDoesNotTickOffTheWrongReminder() async throws {
        let store = ProbeReminderStore()
        seed(store, StoredReminder(id: "r1", title: "Einkauf planen", list: "Einkauf",
                                   notes: "an Milch denken"))
        let outcome = try await run(#"{"action":"complete","find":"Milch"}"#, store)
        XCTAssertEqual(store.stored.first?.isCompleted, false)
        XCTAssertTrue(outcome.text.hasPrefix(L.t("rem_not_found")), outcome.text)
    }

    func testDeletingRemovesTheReminder() async throws {
        let store = ProbeReminderStore()
        seed(store, StoredReminder(id: "r1", title: "Zahnarzt", list: "Erinnerungen"))
        let outcome = try await run(#"{"action":"delete","find":"Zahnarzt"}"#, store)
        XCTAssertTrue(store.stored.isEmpty)
        XCTAssertTrue(outcome.text.contains("Zahnarzt"), outcome.text)
    }

    func testChangingMovesTheDueTimeWithoutTouchingTheTitle() async throws {
        let store = ProbeReminderStore()
        seed(store, StoredReminder(id: "r1", title: "Zahnarzt", list: "Erinnerungen",
                                   due: Formatters.eventDate(from: "2026-10-08 09:00")))
        _ = try await run(#"{"action":"update","find":"Zahnarzt","due":"2026-10-08 11:00"}"#, store)
        XCTAssertEqual(store.stored.first?.title, "Zahnarzt")
        XCTAssertEqual(store.stored.first?.due, Formatters.eventDate(from: "2026-10-08 11:00"))
    }

    func testChangingThePlaceResolvesItsCoordinates() async throws {
        let store = ProbeReminderStore()
        seed(store, StoredReminder(id: "r1", title: "Milch", list: "Erinnerungen"))
        let point = GeoPoint(latitude: 48.6, longitude: 10.2, radius: 150)
        _ = try await run(#"{"action":"update","find":"Milch","location":"REWE"}"#, store,
                          FixedPlaceLookup(points: ["REWE": point]))
        XCTAssertEqual(store.stored.first?.place, "REWE")
        XCTAssertEqual(store.coordinates["r1"], point)
    }

    func testAnUpdateWithAnUnknownPlaceChangesNothing() async throws {
        let store = ProbeReminderStore()
        seed(store, StoredReminder(id: "r1", title: "Milch", list: "Erinnerungen"))
        let outcome = try await run(#"{"action":"update","find":"Milch","location":"Nirgendwo"}"#, store)
        XCTAssertTrue(outcome.text.contains("Nirgendwo"), outcome.text)
        XCTAssertNil(store.stored.first?.place)
        XCTAssertTrue(store.coordinates.isEmpty)
    }

    func testReadingAListShowsOnlyThatList() async throws {
        let store = ProbeReminderStore()
        seed(store, StoredReminder(id: "r1", title: "Milch", list: "Einkauf"))
        seed(store, StoredReminder(id: "r2", title: "Brot", list: "Einkauf"))
        seed(store, StoredReminder(id: "r3", title: "Zahnarzt", list: "Erinnerungen"))
        let outcome = try await run(#"{"action":"list","list":"Einkauf"}"#, store)
        XCTAssertTrue(outcome.text.contains("Milch"), outcome.text)
        XCTAssertTrue(outcome.text.contains("Brot"), outcome.text)
        XCTAssertFalse(outcome.text.contains("Zahnarzt"), outcome.text)
        XCTAssertTrue(outcome.trace.contains("anzahl=2"), outcome.trace)
    }

    func testWithoutAListInThePlanTheSentenceNamesNothing() async throws {
        let store = ProbeReminderStore()
        seed(store, StoredReminder(id: "r1", title: "Milch", list: "Einkauf"))
        seed(store, StoredReminder(id: "r2", title: "Zahnarzt", list: "Erinnerungen"))
        let plan = try JSONDecoder().decode(ReminderPlan.self, from: Data(#"{"action":"list"}"#.utf8))
        let outcome = await ReminderFlowRunner(store: store, places: FixedPlaceLookup())
            .run(try XCTUnwrap(ReminderRequest(plan: plan)))
        XCTAssertTrue(outcome.text.contains("Milch"), outcome.text)
        XCTAssertTrue(outcome.text.contains("Zahnarzt"), outcome.text)
    }

    func testTheListFromThePlanSelectsTheReminders() async throws {
        let store = ProbeReminderStore()
        store.listTitles.append("Baumarkt")
        seed(store, StoredReminder(id: "r1", title: "Milch", list: "Einkauf"))
        seed(store, StoredReminder(id: "r2", title: "Schrauben", list: "Baumarkt"))
        let plan = try JSONDecoder().decode(ReminderPlan.self, from: Data(#"{"action":"list","list":"Baumarkt"}"#.utf8))
        let outcome = await ReminderFlowRunner(store: store, places: FixedPlaceLookup())
            .run(try XCTUnwrap(ReminderRequest(plan: plan)))
        XCTAssertTrue(outcome.text.contains("Schrauben"), outcome.text)
        XCTAssertFalse(outcome.text.contains("Milch"), outcome.text)
    }

    func testReadingAShoppingListThatDoesNotExistYetShowsTheOpenReminders() async throws {
        let store = ProbeReminderStore()
        seed(store, StoredReminder(id: "r1", title: "Milch", list: "Einkauf"))
        let outcome = try await run(#"{"action":"list","list":"Kühlschrank"}"#, store)
        XCTAssertTrue(outcome.text.contains("Milch"), outcome.text)
    }

    func testWithoutAccessNothingIsReadOrWritten() async throws {
        let store = ProbeReminderStore()
        store.granted = false
        let outcome = try await run(#"{"action":"create","title":"Milch"}"#, store)
        XCTAssertEqual(outcome.text, L.t("rem_denied"))
        XCTAssertTrue(store.stored.isEmpty)
    }

    func testACreateWithoutADueDateIsStillASavedReminder() async throws {
        let store = ProbeReminderStore()
        let outcome = try await run(#"{"action":"create","title":"Reifen wechseln","allDay":true}"#, store)
        XCTAssertEqual(store.stored.count, 1)
        XCTAssertNil(store.stored.first?.due)
        XCTAssertTrue(outcome.text.contains("Reifen wechseln"), outcome.text)
    }

    func testACreateSurvivesADeviceWithoutAnyList() async throws {
        let store = ProbeReminderStore()
        store.listTitles = []
        let point = GeoPoint(latitude: 52.5, longitude: 13.4, radius: 150)
        let outcome = try await run(#"{"action":"create","title":"Milch kaufen","location":"REWE"}"#,
                                    store, FixedPlaceLookup(points: ["REWE": point]))
        XCTAssertEqual(store.stored.count, 1)
        XCTAssertEqual(store.stored.first?.list, "Erinnerungen")
        XCTAssertFalse(outcome.text.isEmpty)
    }

    func testUpdatingMovesToAListTheUserNamed() async throws {
        let store = ProbeReminderStore()
        seed(store, StoredReminder(id: "r1", title: "Milch", list: "Einkauf"))
        _ = try await run(#"{"action":"update","find":"Milch","list":"Erinnerungen"}"#, store)
        XCTAssertEqual(store.stored.first?.list, "Erinnerungen")
    }
}
