@testable import GwenMobileFeatureCore
import Translation
import XCTest
import GwenMobileKit

final class TranslationCoreTests: GwenTestCase {
    func testTheProblemAlertCarriesCopyAndSettings() {
        XCTAssertEqual(TranslationProblem.nothingToTranslate.alert.message, L.t("translate_no_text"))
        XCTAssertFalse(TranslationProblem.nothingToTranslate.alert.openSettings)
        let missing = TranslationProblem.packMissing("fr")
        XCTAssertEqual(missing.alert.message,
                       L.fmt("translate_pack_missing", TranslationLanguages.named("fr")))
        XCTAssertTrue(missing.alert.openSettings)
        let model = TranslationProblem.model("kaputt")
        XCTAssertEqual(model.alert.message, L.friendlyError("kaputt").message)
        XCTAssertEqual(model.alert.detail, L.t("translate_failed"))
        XCTAssertEqual(TranslationProblem.unsupportedPair("nl").alert.message,
                       L.fmt("translate_pair_unsupported", TranslationLanguages.named("nl")))
        XCTAssertEqual(TranslationProblem.device("grund").alert.detail, "grund")
    }

    func testProblemsMapFromStatusAndKeepTheTarget() {
        XCTAssertEqual(TranslationProblem.from(status: .packMissing, target: "fr"), .packMissing("fr"))
        XCTAssertEqual(TranslationProblem.from(status: .unsupportedPair, target: "nl"), .unsupportedPair("nl"))
        XCTAssertEqual(TranslationProblem.from(status: .ready, target: "fr"), .device(""))
    }

    func testSourceCodePrefersExplicitThenDetectedThenTheAppLanguage() {
        let explicit = TranslationJob(text: "Hallo", targetCode: "fr", sourceCode: "en")
        XCTAssertEqual(OnDeviceTranslation.sourceCode(for: explicit), "en")
        let detected = TranslationJob(text: "This is a longer English sentence to detect the language.",
                                      targetCode: "fr", sourceCode: nil)
        XCTAssertEqual(OnDeviceTranslation.sourceCode(for: detected), "en")
        let nothing = TranslationJob(text: "12345", targetCode: "fr", sourceCode: nil)
        XCTAssertEqual(OnDeviceTranslation.sourceCode(for: nothing), L.lang.rawValue)
    }

    func testStitchUsesTheClientIdentifiers() {
        let source = Locale.Language(identifier: "de")
        let target = Locale.Language(identifier: "en")
        let responses = [TranslationSession.Response(sourceLanguage: source, targetLanguage: target,
                                                     sourceText: "Hallo", targetText: "Hello",
                                                     clientIdentifier: "0")]
        XCTAssertEqual(OnDeviceTranslation.stitch(chunks: ["Hallo", "Welt"], responses: responses), "HelloWelt")
        let broken = [TranslationSession.Response(sourceLanguage: source, targetLanguage: target,
                                                  sourceText: "Hallo", targetText: "",
                                                  clientIdentifier: "0"),
                      TranslationSession.Response(sourceLanguage: source, targetLanguage: target,
                                                  sourceText: "Welt", targetText: "World",
                                                  clientIdentifier: "9"),
                      TranslationSession.Response(sourceLanguage: source, targetLanguage: target,
                                                  sourceText: "Welt", targetText: "Monde",
                                                  clientIdentifier: "eins")]
        XCTAssertEqual(OnDeviceTranslation.stitch(chunks: ["Hallo", "Welt"], responses: broken), "HalloWelt")
    }

    func testTranslationErrorsBecomeProblems() {
        XCTAssertEqual(OnDeviceTranslation.problem(for: TranslationError.notInstalled), .packMissing(""))
        XCTAssertEqual(OnDeviceTranslation.problem(for: TranslationError.unsupportedLanguagePairing),
                       .unsupportedPair(""))
        if case .device = OnDeviceTranslation.problem(for: NSError(domain: "test", code: 1)) {
            return
        }
        XCTFail("unbekannter Fehler muss als Geräteproblem ankommen")
    }

    func testNormalizedReadsAliasesPrimariesAndUnknownCodes() {
        XCTAssertEqual(OnDeviceTranslation.normalized("pt-BR"), "pt")
        XCTAssertEqual(OnDeviceTranslation.normalized("zh-Hans-CN"), "zh-Hans")
        XCTAssertEqual(OnDeviceTranslation.normalized("zh-Hant"), "zh-Hant")
        XCTAssertEqual(OnDeviceTranslation.normalized("zh-Hant-TW"), "zh-Hant")
        XCTAssertEqual(OnDeviceTranslation.normalized("fr-CA"), "fr")
        XCTAssertNil(OnDeviceTranslation.normalized(""))
        XCTAssertNil(OnDeviceTranslation.normalized("xx"))
    }
}

final class TranslationFlowFallbackTests: GwenTestCase {
    func testIsUsableNeedsAllThreeParts() {
        XCTAssertFalse(TranslationCredentials(baseURL: "", apiKey: "k", model: "m", thinking: .nothing).isUsable)
        XCTAssertFalse(TranslationCredentials(baseURL: "u", apiKey: "", model: "m", thinking: .nothing).isUsable)
        XCTAssertFalse(TranslationCredentials(baseURL: "u", apiKey: "k", model: "", thinking: .nothing).isUsable)
        XCTAssertTrue(TranslationCredentials(baseURL: "u", apiKey: "k", model: "m", thinking: .nothing).isUsable)
    }

    func testThePromptNamesKnownAndUnknownTargets() {
        let known = ModelTranslation.prompt(for: TranslationJob(text: "Hallo", targetCode: "fr"))
        XCTAssertTrue(known.contains("fr"))
        let unknown = ModelTranslation.prompt(for: TranslationJob(text: "Hallo", targetCode: "xx"))
        XCTAssertTrue(unknown.contains("xx"))
        let withSource = ModelTranslation.prompt(for: TranslationJob(text: "Hallo", targetCode: "fr",
                                                                    sourceCode: "de"))
        XCTAssertTrue(withSource.contains("de"))
    }
}
