import XCTest
@testable import GwenMobile

final class AnswerErrorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        L.apply(.de)
    }

    func testModelSafetyRejectionIsReportedAsContentProblem() {
        let text = AnswerError.model("DataInspectionFailed: green net", model: "wan2.7-image",
                                    generic: L.t("err_generic"))
        XCTAssertTrue(text.contains(L.t("err_data_inspection")))
    }

    func testModelTimeoutUsesTheImageTimeoutWord() {
        XCTAssertTrue(AnswerError.model("request timed out", model: nil, generic: "G:")
            .contains(L.t("err_timeout")))
    }

    func testWebFailureIsNeverReportedAsImageGeneration() {
        let text = AnswerError.other("A TLS error caused the secure connection to fail.",
                                    generic: L.t("err_web_generic"))
        XCTAssertTrue(text.contains(L.t("net_tls_blocked")), text)
        XCTAssertFalse(text.contains(L.t("err_generic")), text)
        XCTAssertFalse(text.contains(L.t("err_timeout")), text)
    }

    func testTranslatedAPIErrorWinsOverTheContextPrefix() {
        let text = AnswerError.other("Invalid API key", model: "qwen3.8-flash",
                                    generic: L.t("err_web_generic"))
        XCTAssertTrue(text.contains(L.t("err_bad_key")))
    }

    func testRawDetailIsCapped() {
        let text = AnswerError.other(String(repeating: "e", count: 300), generic: "G:")
        XCTAssertEqual(text.count, AnswerError.marker.count + "G:".count + AnswerError.rawDetailLimit)
    }
}
