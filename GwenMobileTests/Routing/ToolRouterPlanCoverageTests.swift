@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class ToolRouterPlanCoverageTests: GwenTestCase {
    override func tearDown() {
        MockHTTP.uninstall()
        super.tearDown()
    }

    private func combinedResponse() -> Data {
        let content = #"{"wishes":["Wie wird das Wetter?","Male eine Katze"]}"#
        let message: [String: Any] = [
            "content": content,
            "tool_calls": [["id": "c1", "type": "function",
                            "function": ["name": ToolRouter.answerTool, "arguments": "{}"]]]
        ]
        let body: [String: Any] = ["choices": [["message": message]]]
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }

    private func ask(_ text: String = "Wie wird das Wetter? Male eine Katze") -> RouterAsk {
        RouterAsk(baseURL: "https://q.test/v1", key: "k", model: "m", text: text,
                  context: SendContext(), history: [], thinking: .nothing)
    }

    func testTheWholeRouterStepsRun() async {
        let response = combinedResponse()
        MockHTTP.install { _ in (200, response) }
        let plan = await ToolRouter.plan(ask())
        XCTAssertFalse(plan.actions.isEmpty)
        XCTAssertEqual(plan.actions.first?.stepKind, .chat)
    }

    func testTheRouterStepsWithoutAReadableSplit() async {
        let text = ToolCallPayload.message([], content: "keine Wünsche")
        MockHTTP.install { _ in (200, text) }
        let plan = await ToolRouter.plan(ask("Nur eine Frage"))
        XCTAssertFalse(plan.actions.isEmpty)
    }

    func testAVideoWishTheRouterMisreadIsCaughtByTheVideoCheck() async {
        let content = #"{"wishes":["Erstelle ein 10-Sekunden-Video von einem Paar"],"independent":[],"places":[""],"lists":[""]}"#
        let message: [String: Any] = [
            "content": content,
            "tool_calls": [["id": "c1", "type": "function",
                            "function": ["name": ToolRouter.answerTool, "arguments": "{}"]]]
        ]
        let body: [String: Any] = ["choices": [["message": message]]]
        let combined = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        MockHTTP.install { request in
            let body = MockHTTP.body(of: request)
            if body.contains("Decide whether one user wish asks") {
                return (200, MockHTTP.completion(#"{"video":true,"duration":10,"ratio":"9:16"}"#))
            }
            return (200, combined)
        }
        let ask = RouterAsk(baseURL: "https://q.test/v1", key: "k", model: "m",
                            text: "Erstelle ein 10-Sekunden-Video von einem Paar",
                            context: SendContext(), history: [], thinking: .nothing,
                            videoGenerationAvailable: true)
        let plan = await ToolRouter.plan(ask)
        XCTAssertEqual(plan.actions.map(\.stepKind), [.video])
        guard case .videoCreate(let request) = plan.primary.route else {
            return XCTFail("route was \(plan.primary.route)")
        }
        XCTAssertEqual(request.clampedDuration, 10)
        XCTAssertEqual(request.ratio, .portrait)
    }

    func testAVideoWishFromTheSplitterBecomesACreateVideoStep() async {
        let content = #"{"wishes":["Erstelle ein 10-Sekunden-Video von einem Paar"],"independent":[],"places":[""],"lists":[""],"videos":[1],"video_seconds":["10"],"video_ratios":[""]}"#
        let message: [String: Any] = [
            "content": content,
            "tool_calls": [["id": "c1", "type": "function",
                            "function": ["name": ToolRouter.answerTool, "arguments": "{}"]]]
        ]
        let body: [String: Any] = ["choices": [["message": message]]]
        let response = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        MockHTTP.install { _ in (200, response) }
        let plan = await ToolRouter.plan(ask("Erstelle ein 10-Sekunden-Video von einem Paar"))
        XCTAssertEqual(plan.actions.map(\.stepKind), [.video])
        guard case .videoCreate(let request) = plan.primary.route else {
            return XCTFail("route was \(plan.primary.route)")
        }
        XCTAssertEqual(request.clampedDuration, 10)
    }

    func testTheRouterStepsWithADocumentAndHistory() async {
        let response = combinedResponse()
        MockHTTP.install { _ in (200, response) }
        let history = [ChatMessage(role: .user, text: "Alt"),
                       ChatMessage(role: .assistant, text: "Antwort")]
        var context = SendContext()
        context.scannedDocument = true
        let router = RouterAsk(baseURL: "https://q.test/v1", key: "k", model: "m",
                               text: "Fasse das zusammen", context: context, history: history,
                               picture: Data([1, 2, 3]), catalog: "katalog", eraseHistoryWord: "löschen",
                               document: "Dokumenttext", thinking: .nothing, watchCatalog: "wechsel")
        let plan = await ToolRouter.plan(router)
        XCTAssertFalse(plan.actions.isEmpty)
    }
}
