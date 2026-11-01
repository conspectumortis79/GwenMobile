@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class BubbleClaimNoteTests: GwenTestCase {
    private func result(_ verdict: ClaimVerdict, sources: [Int] = [1],
                        contradicts: [Int] = []) -> SourceReview.ClaimResult {
        SourceReview.ClaimResult(claim: "Berlin hat 9 Millionen Einwohner", verdict: verdict,
                                 sources: sources, contradicts: contradicts)
    }

    func testTheAlertTitlesNameTheVerdict() {
        XCTAssertEqual(Bubble.claimAlertTitle(result(.unsupported)), L.t("source_inline_unsupported"))
        XCTAssertEqual(Bubble.claimAlertTitle(result(.contradicted)), L.t("source_inline_contradicted"))
    }

    func testTheAlertMessageCarriesTheStatementAndItsSources() {
        let message = Bubble.claimAlertMessage(result(.contradicted, sources: [4], contradicts: [3]))
        XCTAssertTrue(message.contains("Berlin hat 9 Millionen Einwohner"), message)
        XCTAssertTrue(message.contains("[4]"), message)
        XCTAssertTrue(message.contains("[3]"), message)
    }

    func testAStatementWithoutSourcesKeepsThePlainAlertMessage() {
        XCTAssertEqual(Bubble.claimAlertMessage(result(.unsupported, sources: [])),
                       "Berlin hat 9 Millionen Einwohner")
    }
}
