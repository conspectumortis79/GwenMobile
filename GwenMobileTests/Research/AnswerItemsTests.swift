@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class AnswerItemsTests: XCTestCase {
    func testEveryBulletAndNumberedLineIsOneItem() {
        let text = "Aktuelle Meldungen:\n\n- **A**: eins\n- **B**: zwei\n* drei\n\u{2022} vier\n1. fünf\n2) sechs\n  - eingerückt"
        XCTAssertEqual(AnswerItems.count(in: text), 7)
    }

    func testProseAndNumbersInsideSentencesAreNoItems() {
        let text = "Es ist 2026. Das Theater kostet 242 Millionen Euro.\n-kein Punkt\n2026 war ein Jahr."
        XCTAssertEqual(AnswerItems.count(in: text), 0)
        XCTAssertEqual(AnswerItems.count(in: ""), 0)
    }
}
