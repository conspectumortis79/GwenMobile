@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class ProductScannerTests: GwenTestCase {
    private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])

    func testTheScanSendsOnePictureWithTheProductPrompt() throws {
        let request = try VisionProductScanner.makeRequest(baseURL: "https://api.test/v1", key: "k",
                                                          model: "vision", question: "was kostet das",
                                                          image: jpeg, thinking: .nothing)
        let sent = try jsonMessages(of: request)
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(sent.first?["content"] as? String, Prompt.Product.finding())
        let parts = try XCTUnwrap(sent.last?["content"] as? [[String: Any]])
        XCTAssertEqual(parts.count, 2, "ein Text, ein Bild — nie mehr")
        XCTAssertTrue((parts.first?["text"] as? String ?? "").contains(L.t("product_scan_ask")))
        XCTAssertTrue((parts.first?["text"] as? String ?? "").contains("was kostet das"))
        XCTAssertTrue(parts[1]["image_url"] != nil)
    }

    func testTheScanNeverStreamsAndNeverRunsPastItsBudget() throws {
        let request = try VisionProductScanner.makeRequest(baseURL: "https://api.test/v1", key: "k",
                                                          model: "vision", question: "",
                                                          image: jpeg, thinking: .nothing)
        let sent = try jsonData(of: request)
        XCTAssertEqual(sent["stream"] as? Bool, false)
        XCTAssertEqual(sent["model"] as? String, "vision")
        XCTAssertEqual(sent["max_tokens"] as? Int, VisionProductScanner.maxTokens)
        let parts = try XCTUnwrap((try jsonMessages(of: request)).last?["content"] as? [[String: Any]])
        XCTAssertEqual(parts.first?["text"] as? String, L.t("product_scan_ask"))
    }

    func testAnOversizedPictureIsRejectedBeforeTheScanStarts() {
        let oversized = Data(repeating: 0xAB, count: ImagePolicy.uploadByteBudget + 1)
        XCTAssertThrowsError(try VisionProductScanner.makeRequest(baseURL: "https://api.test/v1", key: "k",
                                                                  model: "vision", question: "x",
                                                                  image: oversized, thinking: .nothing))
    }

    func testTheScanOffersNothingButTheProductReport() throws {
        let request = try VisionProductScanner.makeRequest(baseURL: "https://api.test/v1", key: "k",
                                                          model: "vision", question: "x",
                                                          image: jpeg, thinking: .nothing)
        let sent = try jsonData(of: request)
        let tools = try XCTUnwrap(sent["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 1)
        let function = try XCTUnwrap(tools.first?["function"] as? [String: Any])
        XCTAssertEqual(function["name"] as? String, ToolRouter.productTool)
        XCTAssertEqual(sent["tool_choice"] as? String, ToolRouter.forcedChoice)
    }

    func testTheSecondAttemptAsksAgainWithoutForcingTheCall() throws {
        for attempt in [1, 2] {
            let request = try VisionProductScanner.makeRequest(baseURL: "https://api.test/v1", key: "k",
                                                              model: "vision", question: "x",
                                                              image: jpeg, thinking: .nothing,
                                                              toolChoice: VisionProductScanner.toolChoice(
                                                                attempt: attempt))
            let sent = try jsonData(of: request)
            if attempt == 1 {
                XCTAssertEqual(sent["tool_choice"] as? String, ToolRouter.forcedChoice)
            } else {
                XCTAssertNil(sent["tool_choice"])
            }
        }
        XCTAssertEqual(VisionProductScanner.toolChoice(attempt: 1), ToolRouter.forcedChoice)
        XCTAssertEqual(VisionProductScanner.toolChoice(attempt: 2), ToolRouter.automaticChoice)
    }

    func testTheReportToolCarriesExactlyTheFourValuesOfABefund() throws {
        let function = try XCTUnwrap(ToolRouter.productTools().first?["function"] as? [String: Any])
        let parameters = try XCTUnwrap(function["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["required"] as? [String], ["product"])
        let properties = try XCTUnwrap(parameters["properties"] as? [String: Any])
        XCTAssertEqual(Set(properties.keys), Set(["product", "brand", "price", "ean"]))
    }

    func testTheRouterNeverForcesAChoice() {
        XCTAssertNil(ToolRouter.toolFields(maxTokens: ToolRouter.maxTokens,
                                           tools: ToolRouter.tools(attachable: false))["tool_choice"])
    }

    func testALongQuestionIsShortenedButNeverDropped() {
        let text = VisionProductScanner.userText(String(repeating: "wort ", count: 200))
        XCTAssertTrue(text.hasPrefix(L.t("product_scan_ask")), String(text.prefix(40)))
        let lines = text.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertLessThanOrEqual(lines[1].count, VisionProductScanner.maxQuestionChars)
        XCTAssertTrue(lines[1].hasPrefix("wort "), lines[1])
        XCTAssertEqual(VisionProductScanner.userText("was kostet das"),
                       "\(L.t("product_scan_ask"))\nwas kostet das")
        XCTAssertEqual(VisionProductScanner.userText(""), L.t("product_scan_ask"))
        XCTAssertEqual(VisionProductScanner.userText("   ").components(separatedBy: "\n").count, 1,
                      "nur Leerzeichen sind keine Frage")
    }

    func testThePromptHandsTheReportToTheToolAndForbidsInvention() {
        let prompt = Prompt.Product.finding()
        XCTAssertTrue(prompt.contains(ToolRouter.productTool), prompt)
        XCTAssertTrue(prompt.contains("never invent"), prompt)
        XCTAssertTrue(prompt.contains("not printed on it"), prompt)
        XCTAssertFalse(prompt.contains("JSON"), prompt)
    }

    func testOnlyTheProductCallBecomesABefund() throws {
        let data = payload(content: nil, calls: [ToolCallPayload.entry(ToolRouter.productTool,
                                                                       #"{"product":"Jura ENA 4","brand":"Jura"}"#)])
        let call = try XCTUnwrap(VisionProductScanner.reportCall(in: data))
        let finding = ProductFinding(arguments: call.arguments)
        XCTAssertEqual(finding?.product, "Jura ENA 4")
        XCTAssertEqual(finding?.brand, "Jura")
    }

    func testAnotherToolCallIsNoReportOfThePicture() {
        let data = payload(content: nil, calls: [ToolCallPayload.entry(ToolRouter.priceTool, #"{"terms":["Jura"]}"#)])
        XCTAssertNil(VisionProductScanner.reportCall(in: data))
    }

    func testProseInTheAnswerIsNeverReadAsAProduct() {
        let data = payload(content: "Auf dem Bild ist leider kein Produkt zu erkennen.")
        XCTAssertNil(VisionProductScanner.reportCall(in: data))
    }

    func testAnEmptyReportStaysWithoutABefund() {
        let data = payload(content: nil, calls: [ToolCallPayload.entry(ToolRouter.productTool, #"{"product":""}"#)])
        let call = VisionProductScanner.reportCall(in: data)
        XCTAssertNotNil(call)
        XCTAssertNil(call.flatMap { ProductFinding(arguments: $0.arguments) })
    }

    func testTheLiveScannerSwallowsTransportErrors() async {
        MockHTTP.install { _ in (500, Data()) }
        defer { MockHTTP.uninstall() }
        let found = try? await VisionProductScanner().scan(
            baseURL: "https://api.test/v1", key: "k", model: "m", question: "x", image: jpeg,
            thinking: .nothing)
        XCTAssertNil(found)
    }

    func testTheLiveScannerRejectsAnAnswerWithoutTheReportTool() async {
        MockHTTP.install { _ in (200, MockHTTP.completion("Kein Produkt zu sehen.")) }
        defer { MockHTTP.uninstall() }
        let found = try? await VisionProductScanner().scan(
            baseURL: "https://api.test/v1", key: "k", model: "m", question: "x", image: jpeg,
            thinking: .nothing)
        XCTAssertNil(found)
    }

    func testTheLiveScannerRetriesAfterAnUnusableReport() async {
        let attempts = LockedValue(0)
        MockHTTP.install { _ in
            let attempt = attempts.mutate { value in
                value += 1
                return value
            }
            let arguments = attempt == 1 ? #"{"product":""}"# : #"{"product":"Jura ENA 4","brand":"Jura"}"#
            let data = ToolCallPayload.message([ToolCallPayload.entry(ToolRouter.productTool, arguments)])
            return (200, data)
        }
        defer { MockHTTP.uninstall() }
        let found = try? await VisionProductScanner().scan(
            baseURL: "https://api.test/v1", key: "k", model: "m", question: "x", image: jpeg,
            thinking: .nothing)
        XCTAssertEqual(found?.product, "Jura ENA 4")
        XCTAssertEqual(attempts.current, 2)
    }

    func testAScanWithoutAPictureContentStaysWithoutFinding() async throws {
        let empty = Data()
        let found = try await StubScanner(finding: ProductFinding(product: "Jura ENA 4")).scan(
            baseURL: "https://api.test/v1", key: "k", model: "m", question: "x", image: empty,
            thinking: .nothing)
        XCTAssertNil(found)
    }
}

struct StubScanner: ProductScanning {
    let finding: ProductFinding?

    func scan(baseURL: String, key: String, model: String, question: String, image: Data,
              thinking: ThinkingDirective) async throws -> ProductFinding? {
        image.isEmpty ? nil : finding
    }
}
