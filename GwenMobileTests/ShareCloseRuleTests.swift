import XCTest
@testable import GwenMobile

final class ShareCloseRuleTests: XCTestCase {
    func testEmptyRuleIgnoresEveryActivity() {
        let rule = ShareCloseRule()
        XCTAssertFalse(rule.tracksHandover)
        XCTAssertFalse(rule.closes(on: .airDrop))
        XCTAssertFalse(rule.closes(on: .copyToPasteboard))
        XCTAssertFalse(rule.closes(on: nil))
    }

    func testRuleClosesOnlyOnTheRequestedActivity() {
        let rule = ShareCloseRule([.airDrop])
        XCTAssertTrue(rule.tracksHandover)
        XCTAssertTrue(rule.closes(on: .airDrop))
        XCTAssertFalse(rule.closes(on: .mail))
    }

    func testPreviewRequestWithoutActivityTypeNeverCloses() {
        let rule = ShareCloseRule([.airDrop, .print])
        XCTAssertTrue(rule.tracksHandover)
        XCTAssertFalse(rule.closes(on: nil))
        XCTAssertTrue(rule.closes(on: .print))
    }

    func testRulesWithEqualActivitySetsAreEqual() {
        XCTAssertEqual(ShareCloseRule([.airDrop]), ShareCloseRule([.airDrop]))
        XCTAssertNotEqual(ShareCloseRule([.airDrop]), ShareCloseRule())
    }
}
