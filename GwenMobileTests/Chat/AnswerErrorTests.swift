@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class AnswerErrorTests: GwenTestCase {
    func testModelSafetyRejectionIsReportedAsContentProblem() {
        let text = AnswerError.model("DataInspectionFailed: green net", model: "wan2.7-image",
                                    generic: L.t("err_generic"))
        XCTAssertTrue(text.contains(L.t("err_data_inspection")))
    }

    func testModelContentPolicyIsReportedAsSuch() {
        let text = AnswerError.model("content policy violation", model: nil, generic: "G:")
        XCTAssertTrue(text.hasPrefix(AnswerError.marker + L.t("err_content_policy")))
        let api = AnswerError.model(APIError(message: "invalid input", status: 400), model: nil, generic: "G:")
        XCTAssertTrue(api.contains(L.t("err_invalid_input")))
    }

    func testModelTimeoutUsesTheImageTimeoutWord() {
        XCTAssertTrue(AnswerError.model("invalid input parameter", model: nil, generic: "G:")
            .hasPrefix(AnswerError.marker + L.t("err_invalid_input")))
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

    func testFullSentenceGenericDoesNotDuplicateOrGlueTheError() {
        let place = L.t("place_none_found")
        XCTAssertEqual(AnswerError.other(place, generic: place), AnswerError.marker + place)
        XCTAssertEqual(AnswerError.other("boom", generic: place), AnswerError.marker + place + " boom")
        let weather = L.t("err_weather_generic")
        XCTAssertEqual(AnswerError.other("boom", generic: weather), AnswerError.marker + weather + " boom")
    }

    func testRawDetailIsCapped() {
        let text = AnswerError.other(String(repeating: "e", count: 300), generic: "G:")
        XCTAssertEqual(text.count, AnswerError.marker.count + "G:".count + AnswerError.rawDetailLimit)
    }

    func testUntranslatedChatFailureCarriesTheChatPrefix() {
        let text = AnswerError.other("Something odd happened upstream",
                                      model: "qwen3.8-flash", generic: L.t("err_chat_generic"))
        XCTAssertTrue(text.hasPrefix(AnswerError.marker + L.t("err_chat_generic")), text)
        XCTAssertTrue(text.contains("Something odd happened upstream"), text)
        XCTAssertFalse(text.contains(L.t("err_generic")), text)
    }

    func testRejectedKeyStillEscalatesThroughTheChatFailureWord() {
        let failure = APIError(message: "Invalid API key", status: 401)
        let text = AnswerError.other(failure, model: "qwen3.8-flash", generic: L.t("err_chat_generic"))
        XCTAssertTrue(text.contains(L.t("err_bad_key")), text)
        XCTAssertTrue(L.friendlyError(failure.message, model: "qwen3.8-flash",
                                      status: failure.status).openSettings)
    }

    func testGoneModelEscalatesThroughTheChatFailureWord() {
        for phrasing in ["model_not_found", "Model not found", "model not exist"] {
            let failure = APIError(message: "\(phrasing): qwen9.9-ultra", status: 404)
            let text = AnswerError.other(failure, model: "qwen9.9-ultra", generic: L.t("err_chat_generic"))
            XCTAssertTrue(text.contains("qwen9.9-ultra"), "\(phrasing) -> \(text)")
            XCTAssertFalse(text.contains(L.t("err_chat_generic")), "\(phrasing) -> \(text)")
        }
    }

    func testChatErrorWithoutAWordsStillCarriesTheChatWordAndTheRawText() {
        let failure = APIError(message: "The model qwen9.9-ultra does not exist", status: 404)
        let text = AnswerError.other(failure, model: "qwen9.9-ultra", generic: L.t("err_chat_generic"))
        XCTAssertEqual(text, AnswerError.marker + L.t("err_chat_generic")
                       + "The model qwen9.9-ultra does not exist")
    }
}
