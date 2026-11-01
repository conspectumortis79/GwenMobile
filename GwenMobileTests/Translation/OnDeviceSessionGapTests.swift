@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import Translation
import XCTest
import GwenMobileKit

@MainActor
final class OnDeviceSessionGapTests: GwenTestCase {
    func testTheOnDeviceTranslationUsesTheBatchSeam() async throws {
        let job = TranslationJob(text: "Guten Morgen. Wie geht es dir?", targetCode: "fr")
        OnDeviceTranslation.batch = { chunks, source, target in
            chunks.enumerated().map { index, text in
                TranslationSession.Response(sourceLanguage: source, targetLanguage: target,
                                            sourceText: text, targetText: "FR:\(text)",
                                            clientIdentifier: "\(index)")
            }
        }
        let text = try await OnDeviceTranslation.translate(job)
        XCTAssertTrue(text.contains("FR:"))
        OnDeviceTranslation.batch = { _, _, _ in throw TranslationError.notInstalled }
        do {
            _ = try await OnDeviceTranslation.translate(job)
            XCTFail("erwartet Fehler")
        } catch let problem as TranslationProblem {
            _ = problem
        }
        OnDeviceTranslation.batch = { _, _, _ in throw TranslationError.unsupportedLanguagePairing }
        _ = try? await OnDeviceTranslation.translate(job)
        OnDeviceTranslation.batch = { _, _, _ in throw APIError(message: "kaputt") }
        _ = try? await OnDeviceTranslation.translate(job)
        let empty = TranslationJob(text: "   \n ", targetCode: "fr")
        do {
            _ = try await OnDeviceTranslation.translate(empty)
            XCTFail("erwartet Fehler")
        } catch {}
        _ = try? await OnDeviceTranslation.batch(["Hallo"], Locale.Language(identifier: "de"),
                                                 Locale.Language(identifier: "fr"))
        _ = await OnDeviceTranslation.status(for: job)
        _ = await OnDeviceTranslation.status(for: TranslationJob(text: "Hallo", targetCode: "xx"))
        _ = await OnDeviceTranslation.supportedCodes()
    }
}

@MainActor
extension OnDeviceSessionGapTests {
    func testTheTranslationFlowUsesTheOnDevicePath() async throws {
        OnDeviceTranslation.batch = { chunks, source, target in
            chunks.enumerated().map { index, text in
                TranslationSession.Response(sourceLanguage: source, targetLanguage: target,
                                            sourceText: text, targetText: "Ü:\(text)",
                                            clientIdentifier: "\(index)")
            }
        }
        let job = TranslationJob(text: "Guten Morgen", targetCode: "fr")
        OnDeviceTranslation.statusOverride = { _ in .ready }
        let credentials = TranslationCredentials(baseURL: "", apiKey: "", model: "",
                                                 thinking: .nothing)
        let result = try await TranslationFlow.run(job, credentials: credentials)
        XCTAssertTrue(result.onDevice)
        XCTAssertTrue(result.text.contains("Ü:"))
        OnDeviceTranslation.statusOverride = { _ in .packMissing }
        do {
            _ = try await TranslationFlow.run(job, credentials: credentials)
            XCTFail("erwartet Fehler")
        } catch {}
        OnDeviceTranslation.statusOverride = nil
        let usable = TranslationCredentials(baseURL: "https://q.test/v1", apiKey: "k", model: "m",
                                            thinking: .nothing)
        MockHTTP.install { _ in
            (200, ToolCallPayload.call(ToolRouter.reportTranslationTool, ["translation": "Bonjour"]))
        }
        let model = try await TranslationFlow.run(job, credentials: usable)
        XCTAssertFalse(model.onDevice)
        MockHTTP.install { _ in (500, Data("kaputt".utf8)) }
        do {
            _ = try await TranslationFlow.run(job, credentials: usable)
            XCTFail("erwartet Fehler")
        } catch {}
        MockHTTP.uninstall()
    }
}
