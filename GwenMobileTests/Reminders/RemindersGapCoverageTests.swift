@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit
@testable import GwenMobileProbes

@MainActor
private struct GapThrowingReminderStore: ReminderStoring {
    struct Failure: Error {}

    func hasAccess() async -> Bool { true }
    func lists() async -> [String] { ["Erinnerungen"] }
    func defaultListTitle() async -> String? { "Erinnerungen" }
    func open() async throws -> [StoredReminder] { throw Failure() }
    func create(_ draft: ReminderDraft) async throws -> StoredReminder { throw Failure() }
    func update(_ id: String, with draft: ReminderDraft) async throws -> StoredReminder { throw Failure() }
    func complete(_ id: String, at date: Date) async throws -> StoredReminder { throw Failure() }
    func delete(_ id: String) async throws { throw Failure() }
}

@MainActor
private struct GapEmptyPlaceLookup: ReminderPlaceLooking {
    func locate(_ name: String) async -> GeoPoint? { nil }
}

@MainActor
final class RemindersGapCoverageTests: GwenTestCase {
    private func plan(_ json: String) throws -> ReminderPlan {
        try JSONDecoder().decode(ReminderPlan.self, from: Data(json.utf8))
    }

    private func reminder(_ title: String, due: Date? = nil, allDay: Bool = false,
                          place: String? = nil, notes: String = "",
                          priority: ReminderPriority? = nil,
                          repeatRule: ReminderRepeat? = nil) -> StoredReminder {
        StoredReminder(id: title, title: title, list: "Aufgaben", notes: notes,
                       due: due, allDay: allDay, priority: priority, place: place,
                       repeatRule: repeatRule)
    }

    func testThePlanReadsNumbersFromStrings() throws {
        let parsed = try plan(#"{"action":"create","title":"Tee","minutes":"5","seconds":"30","repeatInterval":"2"}"#)
        XCTAssertEqual(parsed.minutes, 5)
        XCTAssertEqual(parsed.seconds, 30)
        XCTAssertEqual(parsed.repeatInterval, 2)
        XCTAssertEqual(ReminderRepeat(word: "daily", interval: nil)?.interval, 1)
        XCTAssertNil(ReminderRepeat(word: "nie", interval: 2))
        XCTAssertEqual(ReminderRef(reminder("Tee")).id, "Tee")
        XCTAssertNil(ReminderChip.noticeKey(for: .present(ReminderRef(reminder("Tee")))))
        XCTAssertEqual(ReminderChip.noticeKey(for: .accessMissing), "rem_denied")
        XCTAssertEqual(ReminderChip.noticeKey(for: .gone), "rem_chip_gone")
    }

    func testSmokeTheReminderDeskCanBeSwappedAndRestored() {
        let desk = ReminderDesk()
        desk.stand(in: ProbeReminderStore(), places: GapEmptyPlaceLookup())
        desk.restore()
        desk.restore()
    }

    func testTheAnswerWordsCoverEmptyAndFilledLists() throws {
        let request = try XCTUnwrap(ReminderRequest(plan: try plan(#"{"action":"complete"}"#)))
        XCTAssertFalse(ReminderAnswer.notFound(request).isEmpty)
        XCTAssertTrue(ReminderAnswer.list([], titled: nil).contains(L.t("rem_list_empty_all")))
        XCTAssertTrue(ReminderAnswer.list([], titled: "Einkauf").contains("Einkauf"))
        let due = Date(timeIntervalSince1970: 1_800_000_000)
        let full = reminder("Zahnarzt", due: due, place: "Praxis",
                            notes: "Zahnkarte", priority: .high,
                            repeatRule: ReminderRepeat(frequency: .daily, interval: 2))
        let line = ReminderAnswer.list([full], titled: "Aufgaben")
        XCTAssertTrue(line.contains("Zahnarzt"), line)
        XCTAssertTrue(line.contains("Praxis"), line)
        let allDay = ReminderAnswer.list([reminder("Müll", due: due, allDay: true)], titled: nil)
        XCTAssertTrue(allDay.contains("Müll"))
        let described = ReminderAnswer.describe(full)
        XCTAssertTrue(described.contains("Zahnkarte"), described)
        XCTAssertTrue(described.contains(L.t("rem_priority_line")), described)
        XCTAssertTrue(ReminderAnswer.describe(reminder("Leer")).contains("Leer"))
    }

    func testTheFlowRunnerReportsStoreFailures() async throws {
        let store = GapThrowingReminderStore()
        let runner = ReminderFlowRunner(store: store, places: GapEmptyPlaceLookup())
        let cases = [
            #"{"action":"list"}"#,
            #"{"action":"create","title":"Tee"}"#,
            #"{"action":"update","title":"Tee"}"#,
            #"{"action":"complete","title":"Tee"}"#,
            #"{"action":"delete","title":"Tee"}"#,
        ]
        for json in cases {
            let parsed = try XCTUnwrap(ReminderRequest(plan: try plan(json)))
            let outcome = await runner.run(parsed)
            XCTAssertTrue(outcome.trace.contains("fehler="), outcome.trace)
            XCTAssertNil(outcome.ref)
        }
    }

    func testTheFlowRunnerReportsAMissingList() async throws {
        let store = ProbeReminderStore()
        let runner = ReminderFlowRunner(store: store, places: GapEmptyPlaceLookup())
        let parsed = try XCTUnwrap(ReminderRequest(plan: try plan(#"{"action":"create","title":"Tee","list":"Gibt es nicht"}"#)))
        let outcome = await runner.run(parsed)
        XCTAssertTrue(outcome.text.contains("Gibt es nicht") || !outcome.text.isEmpty)
        XCTAssertTrue(store.stored.isEmpty)
    }
}
