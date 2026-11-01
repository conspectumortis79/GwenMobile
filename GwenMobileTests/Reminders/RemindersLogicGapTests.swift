@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit
@testable import GwenMobileProbes

@MainActor
final class RemindersLogicGapTests: GwenTestCase {
    private func request(_ json: String) throws -> ReminderRequest {
        let plan = try JSONDecoder().decode(ReminderPlan.self, from: Data(json.utf8))
        return try XCTUnwrap(ReminderRequest(plan: plan))
    }

    func testTheRepeatTextNamesEveryFrequency() {
        for frequency in ReminderRepeat.Frequency.allCases {
            XCTAssertFalse(ReminderAnswer.repeatText(ReminderRepeat(frequency: frequency,
                                                                    interval: 1)).isEmpty,
                           "\(frequency)")
            XCTAssertFalse(ReminderAnswer.repeatText(ReminderRepeat(frequency: frequency,
                                                                    interval: 3)).isEmpty,
                           "\(frequency)")
        }
        XCTAssertFalse(ReminderAnswer.repeatText(ReminderRepeat(frequency: .daily,
                                                                interval: 0)).isEmpty)
    }

    func testTheRunnerReadsAndChangesLists() async throws {
        let store = ProbeReminderStore()
        let runner = ReminderFlowRunner(store: store, places: ProbePlaceLookup())
        _ = await runner.run(try request(#"{"action":"create","title":"Milch"}"#))
        let listed = await runner.run(try request(#"{"action":"list","list":"Einkauf"}"#))
        XCTAssertFalse(listed.text.isEmpty)
        _ = await runner.run(try request(#"{"action":"list","list":"Gibt es nicht"}"#))
        let unmatched = await runner.run(try request(#"{"action":"create","title":"Brot","list":"Unbekannt"}"#))
        XCTAssertFalse(unmatched.text.isEmpty)
        let changed = await runner.run(try request(#"{"action":"update","find":"Milch","list":"Unbekannt"}"#))
        XCTAssertFalse(changed.text.isEmpty)
        _ = await runner.run(try request(#"{"action":"complete","find":"Milch"}"#))
        _ = await runner.run(try request(#"{"action":"delete","find":"Milch"}"#))
        let noAccess = ProbeReminderStore()
        noAccess.granted = false
        let denied = await ReminderFlowRunner(store: noAccess, places: ProbePlaceLookup())
            .run(try request(#"{"action":"list"}"#))
        XCTAssertNil(denied.ref)
    }
}
