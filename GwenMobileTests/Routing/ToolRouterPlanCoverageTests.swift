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

    func testAPictureWishIsNotTurnedIntoAVideoByTheVideoCheck() async {
        let wish = "Zeichne mir einen Leuchtturm bei Nacht im Comic-Stil."
        let split = #"{"wishes":["Zeichne mir einen Leuchtturm bei Nacht im Comic-Stil."],"independent":[],"places":[""],"lists":[""]}"#
        let splitter = ToolCallPayload.message([], content: split)
        let picture = ToolCallPayload.call(ToolRouter.createTool,
                                           #"{"prompt":"Leuchtturm bei Nacht im Comic-Stil"}"#)
        let checks = LockedValue(0)
        MockHTTP.install { request in
            let body = MockHTTP.body(of: request)
            if body.contains("Decide whether one user wish asks") {
                checks.mutate { $0 += 1 }
                return (200, MockHTTP.completion(#"{"video":true}"#))
            }
            guard body.contains("\"tools\"") else { return (200, splitter) }
            return (200, picture)
        }
        let ask = RouterAsk(baseURL: "https://q.test/v1", key: "k", model: "m", text: wish,
                            context: SendContext(), history: [], thinking: .nothing,
                            videoGenerationAvailable: true)
        let plan = await ToolRouter.plan(ask)
        XCTAssertEqual(checks.current, 0, "ein bereits erkannter Bildwunsch darf nicht zur Videopruefung gehen")
        XCTAssertEqual(plan.actions.map(\.stepKind), [.create])
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

    func testTheRouterPlanRunsParallelWithoutPerWishQuestions() async {
        let wishes = #"{"wishes":["Wie wird das Wetter?","Suche die Einwohnerzahl"],"independent":[1,2],"places":["",""],"lists":["",""]}"#
        let answerEntry = ToolCallPayload.entry(ToolRouter.answerTool, #"{"independent":true}"#, id: "c1")
        let searchEntry = ToolCallPayload.entry(ToolRouter.searchTool,
                                                #"{"query":"Einwohner Deutschland","independent":true}"#,
                                                id: "c2")
        let calls = ToolCallPayload.message([answerEntry, searchEntry])
        let answer = ToolCallPayload.message([answerEntry])
        let splitter = ToolCallPayload.message([], content: wishes)
        let routerRequests = LockedValue(0)
        let wishRequests = LockedValue(0)
        MockHTTP.install { request in
            let body = MockHTTP.body(of: request)
            guard body.contains("\"tools\"") else { return (200, splitter) }
            if body.contains("already split the user's message") {
                wishRequests.mutate { $0 += 1 }
                return (200, answer)
            }
            routerRequests.mutate { $0 += 1 }
            return (200, calls)
        }
        let plan = await ToolRouter.plan(ask("Wie wird das Wetter? Suche die Einwohnerzahl"))
        XCTAssertEqual(routerRequests.current, 1, "der Plan kommt aus einem Router-Response")
        XCTAssertEqual(wishRequests.current, 0, "der Router zerlegt selbst, also keine Nachfrage je Wunsch")
        XCTAssertEqual(plan.actions.map(\.stepKind), [.chat, .search])
        XCTAssertTrue(plan.actions.allSatisfy(\.standalone), "beide Aufrufe stehen allein")
        XCTAssertEqual(plan.actions.map(\.wish), ["Wie wird das Wetter?", "Suche die Einwohnerzahl"])
    }

    func testASingleRouterCallStillAsksEveryWishOnItsOwn() async {
        let wishes = #"{"wishes":["Wie wird das Wetter?","Suche die Einwohnerzahl"],"independent":[1,2],"places":["",""],"lists":["",""]}"#
        let answer = ToolCallPayload.call(ToolRouter.answerTool, "{}")
        let weather = ToolCallPayload.call(ToolRouter.weatherTool, #"{"day":"today"}"#)
        let search = ToolCallPayload.call(ToolRouter.searchTool, #"{"query":"Einwohner Deutschland"}"#)
        let routerRequests = LockedValue(0)
        MockHTTP.install { request in
            let body = MockHTTP.body(of: request)
            guard body.contains("\"tools\"") else {
                return (200, ToolCallPayload.message([], content: wishes))
            }
            routerRequests.mutate { $0 += 1 }
            if body.contains(#""content":"Suche die Einwohnerzahl""#) { return (200, search) }
            if body.contains(#""content":"Wie wird das Wetter?""#) { return (200, weather) }
            return (200, answer)
        }
        let plan = await ToolRouter.plan(ask("Wie wird das Wetter? Suche die Einwohnerzahl"))
        XCTAssertEqual(plan.actions.map(\.stepKind), [.weather, .search])
        XCTAssertGreaterThan(routerRequests.current, 1,
                             "ein einzelner Aufruf zerlegt nicht, also wird je Wunsch gefragt")
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
