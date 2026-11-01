@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

private extension TranslationCredentials {
    static var unusable: TranslationCredentials {
        TranslationCredentials(baseURL: "", apiKey: "", model: "", thinking: .nothing)
    }
}

final class TranslationFlowTests: GwenTestCase {
    func testEmptyTextIsRefusedBeforeAnythingRuns() async {
        let job = TranslationJob(text: "   \n ", targetCode: "fr")
        do {
            _ = try await TranslationFlow.run(job, credentials: .unusable)
            XCTFail("leerer Text darf keine Übersetzung starten")
        } catch let problem as TranslationProblem {
            XCTAssertEqual(problem, .nothingToTranslate)
            XCTAssertTrue(problem.copy.contains("translate"), problem.copy)
        } catch {
            XCTFail("unerwarteter Fehler \(error)")
        }
    }

    func testWithoutDeviceSupportAndWithoutAccessTheFlowReportsAProblem() async throws {
        let job = TranslationJob(text: "Wo ist der nächste Bahnhof?", targetCode: "fr")
        let status = await OnDeviceTranslation.status(for: job)
        do {
            let done = try await TranslationFlow.run(job, credentials: .unusable)
            XCTAssertTrue(done.onDevice, "nur das Gerät kann ohne Schlüssel übersetzen")
            XCTAssertFalse(done.text.isEmpty)
        } catch let problem as TranslationProblem {
            XCTAssertFalse(problem.copy.isEmpty)
            XCTAssertFalse(problem.copy.hasPrefix("translate_"), problem.copy)
            XCTAssertNotEqual(problem.copy, "translating", problem.copy)
            if status == .ready { XCTFail("bei bereit hätte das Gerät übersetzen müssen: \(problem)") }
        } catch {
            XCTFail("unerwarteter Fehler \(error)")
        }
    }

    func testModelRefusesWithoutCredentials() async {
        let job = TranslationJob(text: "Hallo", targetCode: "en")
        do {
            _ = try await ModelTranslation.translate(job, credentials: .unusable)
            XCTFail("ohne Zugang kann nichts übersetzt werden")
        } catch let problem as TranslationProblem {
            XCTAssertEqual(problem, .model("no api access"))
        } catch {
            XCTFail("unerwarteter Fehler \(error)")
        }
    }

    func testBusyLabelAndSignatureNameThePair() {
        let job = TranslationJob(text: "Hallo", targetCode: "fr", sourceCode: "de")
        XCTAssertEqual(TranslationFlow.busyLabel(for: job), "Translating German → French")
        XCTAssertEqual(TranslationFlow.signature(onDevice: true, job: job),
                       "On-device translation · German → French")
        XCTAssertTrue(TranslationFlow.signature(onDevice: false, job: job).contains("model"))
    }

    func testTheSignatureNamesTheDetectedSourceOfTheDeviceTranslation() {
        let job = TranslationJob(text: "Wo ist der nächste Bahnhof?", targetCode: "fr")
        XCTAssertEqual(job.pairLabel, "Detected language → French")
        let carried = job.withSource(OnDeviceTranslation.sourceCode(for: job))
        XCTAssertEqual(carried.sourceCode, "de")
        XCTAssertEqual(TranslationFlow.signature(onDevice: true, job: carried),
                       "On-device translation · German → French")
        XCTAssertEqual(carried.text, job.text)
        XCTAssertTrue(carried.fromChat == job.fromChat)
    }

    func testAToolTranslationIsReadFromItsField() {
        let data = ToolCallPayload.call(ToolRouter.reportTranslationTool, ["translation": "Bonjour"])
        XCTAssertEqual(ModelTranslation.translation(from: data), "Bonjour")
        let empty = ToolCallPayload.call(ToolRouter.reportTranslationTool, ["translation": "   "])
        XCTAssertNil(ModelTranslation.translation(from: empty))
        let foreign = payload(ToolRouter.translateTool, #"{"target":"fr"}"#)
        XCTAssertNil(ModelTranslation.translation(from: foreign))
    }

    func testModelAnswersAreStrippedOfQuotes() {
        XCTAssertEqual(ModelTranslation.cleaned("„Bonjour“"), "Bonjour")
        XCTAssertEqual(ModelTranslation.cleaned("\"Bonjour\""), "Bonjour")
        XCTAssertEqual(ModelTranslation.cleaned("Bonjour\nComment allez-vous ?"),
                       "Bonjour\nComment allez-vous ?")
        XCTAssertEqual(ModelTranslation.cleaned("  Bonjour  "), "Bonjour")
    }

    func testTheTranslationRequestForcesTheReportTool() throws {
        let job = TranslationJob(text: "Hallo", targetCode: "fr")
        let credentials = TranslationCredentials(baseURL: "https://q.test/v1", apiKey: "k",
                                                 model: "m", thinking: .nothing)
        let request = try ModelTranslation.makeRequest(job, credentials: credentials)
        let body = try XCTUnwrap(jsonBody(of: request))
        XCTAssertEqual(body["tool_choice"] as? String, ToolRouter.forcedChoice)
        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        let names = tools.compactMap { ($0["function"] as? [String: Any])?["name"] as? String }
        XCTAssertEqual(names, [ToolRouter.reportTranslationTool])
    }

    func testPromptCarriesTheTargetLanguageAndTheTool() {
        let prompt = ModelTranslation.prompt(for: TranslationJob(text: "Hallo", targetCode: "fr",
                                                                sourceCode: "de"))
        XCTAssertTrue(prompt.contains("fr (French)"), prompt)
        XCTAssertTrue(prompt.contains("de (German)"), prompt)
        XCTAssertTrue(prompt.contains(ToolRouter.reportTranslationTool), prompt)
        XCTAssertFalse(prompt.contains("{{"), prompt)
    }

    func testSourceCodeFallsBackToDetectionThenToTheAppLanguage() {
        let german = TranslationJob(text: "Wo ist der nächste Bahnhof?", targetCode: "fr")
        XCTAssertEqual(OnDeviceTranslation.sourceCode(for: german), "de")
        let english = TranslationJob(text: "Where is the next station?", targetCode: "fr")
        XCTAssertEqual(OnDeviceTranslation.sourceCode(for: english), "en")
        let named = TranslationJob(text: "Where is the next station?", targetCode: "fr", sourceCode: "de")
        XCTAssertEqual(OnDeviceTranslation.sourceCode(for: named), "de")
    }

    func testDetectedSourceIsNormalisedToCatalogueCodes() {
        XCTAssertEqual(OnDeviceTranslation.detectedSource(of: "Wo ist der nächste Bahnhof?"), "de")
        XCTAssertEqual(OnDeviceTranslation.normalized("zh"), "zh-Hans")
        XCTAssertEqual(OnDeviceTranslation.normalized("zh-Hant"), "zh-Hant")
        XCTAssertEqual(OnDeviceTranslation.normalized("yue"), "zh-Hant")
        XCTAssertEqual(OnDeviceTranslation.normalized("no"), "nb")
        XCTAssertEqual(OnDeviceTranslation.normalized("pt-BR"), "pt")
        XCTAssertNil(OnDeviceTranslation.detectedSource(of: "?!?"))
    }

    func testATranslationOfOnlyWrapperQuotesIsRefused() async {
        let job = TranslationJob(text: "Hallo", targetCode: "fr")
        let credentials = TranslationCredentials(baseURL: "https://api.test/v1", apiKey: "k", model: "m",
                                                 thinking: .nothing)
        MockHTTP.install { _ in
            (200, ToolCallPayload.call(ToolRouter.reportTranslationTool, ["translation": "\" \""]))
        }
        defer { MockHTTP.uninstall() }
        do {
            _ = try await ModelTranslation.translate(job, credentials: credentials)
            XCTFail("erwartet Fehler")
        } catch let problem as TranslationProblem {
            XCTAssertEqual(problem, .model(L.t("translate_failed")))
        } catch {
            XCTFail("unerwarteter Fehler \(error)")
        }
    }

    func testJobDescriptionKeepsTheLogShort() {
        let job = TranslationJob(text: String(repeating: "a", count: 5000), targetCode: "fr", fromChat: true)
        XCTAssertEqual(job.description, "translate → fr (zeichen=5000 zeilen=1)")
        XCTAssertEqual(String(describing: job), job.description)
        XCTAssertEqual(job.trace, "zeichen=5000 zeilen=1")
    }
}
