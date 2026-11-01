@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class ScanRoutingTests: GwenTestCase {
    private func scanFunction() throws -> [String: Any] {
        try toolFunction(ToolRouter.scanTool)
    }

    func testTheScanToolIsOffered() {
        XCTAssertTrue(ToolSchemaNames.of(ToolRouter.tools(attachable: false)).contains(ToolRouter.scanTool))
    }

    func testTheScanToolNamesTheDocumentsAndTheReminder() throws {
        let description = try XCTUnwrap(scanFunction()["description"] as? String)
        XCTAssertTrue(description.contains("invoice"), description)
        XCTAssertTrue(description.contains("receipt"), description)
        XCTAssertTrue(description.contains("authority"), description)
        XCTAssertTrue(description.contains("scan an invoice"), description)
        XCTAssertTrue(description.contains("scan a receipt"), description)
        XCTAssertTrue(description.contains("scan a deadline as a reminder"), description)
        XCTAssertTrue(description.contains("document camera"), description)
        XCTAssertTrue(description.contains("Never use it when the message only asks about documents"),
                      description)
    }

    func testTheScanToolCarriesKindAndReminder() throws {
        let parameters = try XCTUnwrap(scanFunction()["parameters"] as? [String: Any])
        let properties = try XCTUnwrap(parameters["properties"] as? [String: Any])
        let kind = try XCTUnwrap(properties["kind"] as? [String: Any])
        XCTAssertEqual(kind["enum"] as? [String], ScanKind.toolValues)
        XCTAssertNotNil(properties["remind"])
        XCTAssertEqual((parameters["required"] as? [String]) ?? [], [])
    }

    func testAScanCallMapsOntoTheScanRoute() throws {
        let decision = try XCTUnwrap(ToolRouter.decisions(
            from: call(ToolRouter.scanTool, ["kind": "receipt", "remind": true])).first)
        guard case .scanDocument(let request) = decision.route else {
            return XCTFail("scan_document landete nicht im Scan: \(decision.route)")
        }
        XCTAssertEqual(request.kind, .receipt)
        XCTAssertTrue(request.remind)
        XCTAssertEqual(decision.stepKind, .scan)
        XCTAssertEqual(decision.stepDetail, "receipt erinnerung")
    }

    func testAMissingKindAndANamelessDocumentStayCalm() throws {
        let decision = try XCTUnwrap(ToolRouter.decisions(from: call(ToolRouter.scanTool, [:])).first)
        guard case .scanDocument(let request) = decision.route else { return XCTFail("Scan fehlt") }
        XCTAssertEqual(request.kind, .other)
        XCTAssertFalse(request.remind)
        XCTAssertEqual(ScanKind.named("Rechnung"), .other)
        XCTAssertEqual(ScanKind.named("invoice"), .invoice)
    }

    func testTheSystemBlockNamesTheScanTool() {
        let block = ToolRouter.systemBlock(now: "x", context: SendContext(), transcript: "")
        XCTAssertTrue(block.contains(ToolRouter.scanTool), block)
        XCTAssertTrue(block.contains("scan an invoice"), block)
        XCTAssertTrue(block.contains("scan a deadline as a reminder"), block)
    }

    func testAScannedDocumentKeepsTheCameraClosed() {
        let context = SendContext(scannedDocument: true, documentReminder: true)
        let block = ToolRouter.systemBlock(now: "x", context: context, transcript: "",
                                           document: "Stadtwerke München\nZahlbar bis 15.10.2026")
        XCTAssertTrue(block.contains("Never call \(ToolRouter.scanTool)"), block)
        XCTAssertTrue(block.contains("SCANNED DOCUMENT"), block)
        XCTAssertTrue(block.contains("Zahlbar bis 15.10.2026"), block)
        XCTAssertTrue(block.contains(ToolRouter.reminderTool), block)
        XCTAssertTrue(block.contains("take its title and due from the recognized text"), block)
    }

    func testWithoutAScanNoDocumentBlockAppears() {
        let block = ToolRouter.systemBlock(now: "x", context: SendContext(), transcript: "",
                                           document: "geheim")
        XCTAssertFalse(block.contains("geheim"), block)
        XCTAssertFalse(block.contains("SCANNED DOCUMENT"), block)
    }

    func testTheFocusedReminderCallOffersOnlyTheReminderTool() throws {
        let request = try ToolRouter.scanReminderRequest(
            baseURL: "https://example.test/v1", key: "k", model: "m",
            text: "Frist als Erinnerung scannen",
            context: SendContext(scannedDocument: true, documentReminder: true),
            history: [ChatMessage(role: .user, text: "Frist als Erinnerung scannen")],
            document: "Stadtwerke München\nZahlbar bis 15.10.2026", thinking: .nothing)
        let body = try jsonData(of: request)
        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 1)
        let function = try XCTUnwrap(tools.first?["function"] as? [String: Any])
        XCTAssertEqual(function["name"] as? String, ToolRouter.reminderTool)
        XCTAssertEqual(body["tool_choice"] as? String, ToolRouter.forcedChoice)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let system = try XCTUnwrap(messages.first?["content"] as? String)
        XCTAssertTrue(system.contains("Zahlbar bis 15.10.2026"), system)
        XCTAssertTrue(system.contains("SCANNED DOCUMENT"), system)
        XCTAssertTrue(system.contains("exactly one call"), system)
    }

    func testTheAnalysisPlanNeverScansAgain() throws {
        let scan = try XCTUnwrap(ToolRouter.map(name: ToolRouter.scanTool,
                                                arguments: #"{"kind":"receipt"}"#))
        let answer = try XCTUnwrap(ToolRouter.map(name: ToolRouter.answerTool, arguments: "{}"))
        let reminder = try XCTUnwrap(ToolRouter.map(name: ToolRouter.reminderTool,
                                                    arguments: #"{"action":"create","title":"Frist","due":"2026-10-15"}"#))
        XCTAssertEqual(ScanPlan.analysisActions(SendPlan(actions: [scan, answer]), remind: false)
            .map(\.stepKind), [.chat])
        XCTAssertEqual(ScanPlan.analysisActions(SendPlan(actions: [scan]), remind: false)
            .map(\.stepKind), [.chat])
        XCTAssertEqual(ScanPlan.analysisActions(SendPlan(actions: [scan, answer, reminder]), remind: true)
            .map(\.stepKind), [.chat])
        XCTAssertEqual(ScanPlan.analysisActions(SendPlan(actions: [scan, reminder]), remind: false)
            .map(\.stepKind), [.reminder])
    }

    func testTheScanStepKeepsItsPlaceInTheChain() throws {
        let scan = try XCTUnwrap(ToolRouter.map(name: ToolRouter.scanTool,
                                                arguments: #"{"kind":"invoice"}"#))
        let answer = try XCTUnwrap(ToolRouter.map(name: ToolRouter.answerTool, arguments: "{}"))
        let plan = SendPlan.forming([scan, answer])
        XCTAssertEqual(plan.actions.map(\.stepKind), [.scan, .chat])
    }
}
