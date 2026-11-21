@testable import GwenMobileFeatureCore
import XCTest

final class AnswerLengthTests: XCTestCase {
    func testWithoutADetailWishTheAnswerStaysCompact() {
        XCTAssertEqual(AnswerLength.compact.words, 150)
        XCTAssertFalse(AnswerLength.compact.isDetailed)
        XCTAssertNil(AnswerLength.compact.wordsEach)
    }

    func testADetailWishGrowsWithTheNumberOfItems() {
        XCTAssertEqual(AnswerLength.detailed(items: 5).words, 400)
        XCTAssertEqual(AnswerLength.detailed(items: 5).wordsEach, 80)
        XCTAssertEqual(AnswerLength.detailed(items: 8).words, 640)
    }

    func testADetailWishStaysBetweenItsFloorAndItsCeiling() {
        XCTAssertEqual(AnswerLength.detailed(items: 0).words, AnswerLength.detailedFloor)
        XCTAssertNil(AnswerLength.detailed(items: 0).wordsEach)
        XCTAssertEqual(AnswerLength.detailed(items: 2).words, AnswerLength.detailedFloor)
        XCTAssertEqual(AnswerLength.detailed(items: 2).wordsEach, 150)
        XCTAssertEqual(AnswerLength.detailed(items: 20).words, AnswerLength.detailedCeiling)
        XCTAssertEqual(AnswerLength.detailed(items: 20).wordsEach, 35)
        XCTAssertEqual(AnswerLength.detailed(items: -3), AnswerLength.detailed(items: 0))
    }

    func testTheLongestDetailedAnswerStillFitsTheTranscriptOfTheNextTurn() {
        let charactersPerWord = 8
        XCTAssertLessThanOrEqual(AnswerLength.detailedCeiling * charactersPerWord,
                                 ConversationTranscript.defaultAnswerCap)
    }
}
