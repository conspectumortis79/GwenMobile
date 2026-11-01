@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class SourceFilterTests: GwenTestCase {
    private func hit(_ id: Int) -> WebHit {
        Fixtures.hit("Quelle \(id)", "https://s\(id).test/a", "s\(id).test", "Text \(id) zur Frage.")
    }

    private func answer(_ numbers: [Int]) -> Data {
        ToolCallPayload.message([ToolCallPayload.entry(ToolRouter.keepSourcesTool,
                                                       "{\"sources\":\(numbers)}")])
    }

    func testTheFilterKeepsOnlyTheNumbersTheRouterNamed() async {
        let data = answer([1, 3])
        let kept = await ToolRouter.keptSources(baseURL: "https://api.test/v1", key: "k", model: "m",
                                                question: "Nachrichten aus Berlin", hits: [hit(1), hit(2), hit(3)],
                                                thinking: .nothing) { _ in data }
        XCTAssertEqual(kept.map(\.domain), ["s1.test", "s3.test"])
    }

    func testAnExplicitlyEmptySelectionLeavesNoSource() async {
        let data = answer([])
        let kept = await ToolRouter.keptSources(baseURL: "https://api.test/v1", key: "k", model: "m",
                                                question: "Nachrichten aus Berlin", hits: [hit(1), hit(2)],
                                                thinking: .nothing) { _ in data }
        XCTAssertTrue(kept.isEmpty)
    }

    func testAnUnreadableFilterAnswerKeepsEverySource() async {
        let kept = await ToolRouter.keptSources(baseURL: "https://api.test/v1", key: "k", model: "m",
                                                question: "Nachrichten aus Berlin", hits: [hit(1), hit(2)],
                                                thinking: .nothing) { _ in Data("keine Antwort".utf8) }
        XCTAssertEqual(kept.count, 2)
    }

    func testAFailedFilterCallKeepsEverySource() async {
        let kept = await ToolRouter.keptSources(baseURL: "https://api.test/v1", key: "k", model: "m",
                                                question: "Nachrichten aus Berlin", hits: [hit(1), hit(2)],
                                                thinking: .nothing) { _ in
            throw APIError(message: "HTTP 503")
        }
        XCTAssertEqual(kept.count, 2)
    }

    func testOnlyOneSourceIsNeverFilteredThroughTheRouter() async {
        let calls = LockedValue(0)
        let data = answer([1])
        let kept = await ToolRouter.keptSources(baseURL: "https://api.test/v1", key: "k", model: "m",
                                                question: "Nachrichten aus Berlin", hits: [hit(1)],
                                                thinking: .nothing) { _ in
            calls.mutate { $0 += 1 }
            return data
        }
        XCTAssertEqual(calls.current, 0)
        XCTAssertEqual(kept.map(\.domain), ["s1.test"])
    }

    func testTheFilterRequestForcesTheKeepingToolOnTheQuestion() throws {
        let request = try ToolRouter.sourceFilterRequest(baseURL: "https://api.test/v1", key: "k", model: "m",
                                                         question: "Nachrichten aus Berlin",
                                                         hits: [hit(1), hit(2)], thinking: .nothing)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        XCTAssertEqual(body["tool_choice"] as? String, ToolRouter.forcedChoice)
        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        let names = tools.compactMap { ($0["function"] as? [String: Any])?["name"] as? String }
        XCTAssertEqual(names, [ToolRouter.keepSourcesTool])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let system = try XCTUnwrap(messages.first?["content"] as? String)
        XCTAssertFalse(system.contains("{{"), system)
        let user = try XCTUnwrap(messages.last?["content"] as? String)
        XCTAssertTrue(user.contains("Nachrichten aus Berlin"), user)
        XCTAssertTrue(user.contains("s1.test"), user)
        XCTAssertFalse(user.contains("{{"), user)
    }

    func testTheKeepingToolNamesOnlyRealSourceNumbersOnce() throws {
        let data = ToolCallPayload.message([ToolCallPayload.entry(ToolRouter.keepSourcesTool,
                                                                  "{\"sources\":[3,1,3,99,0,2]}")])
        XCTAssertEqual(ToolRouter.sourceIndexes(from: data, count: 3), [2, 0, 1])
    }

    func testHugeOrOverflowingSourceNumbersAreIgnored() throws {
        let data = ToolCallPayload.message([ToolCallPayload.entry(
            ToolRouter.keepSourcesTool,
            "{\"sources\":[1e300,-9223372036854775808,1]}")])
        XCTAssertEqual(ToolRouter.sourceIndexes(from: data, count: 2), [0])
    }

    func testNumbersThatCarryTextStillCount() throws {
        let data = ToolCallPayload.message([ToolCallPayload.entry(ToolRouter.keepSourcesTool,
                                                                  "{\"sources\":[\"1\",\"x\",2]}")])
        XCTAssertEqual(ToolRouter.sourceIndexes(from: data, count: 2), [0, 1])
    }

    func testAMissingToolCallOrForeignToolStaysUnreadable() {
        XCTAssertNil(ToolRouter.sourceIndexes(from: Data("{}".utf8), count: 2))
        let other = ToolCallPayload.message([ToolCallPayload.entry(ToolRouter.answerTool,
                                                                   "{\"sources\":[1]}")])
        XCTAssertNil(ToolRouter.sourceIndexes(from: other, count: 2))
    }

    func testNumbersWithoutRealSourcesStayUnreadable() {
        let data = ToolCallPayload.message([ToolCallPayload.entry(ToolRouter.keepSourcesTool,
                                                                  "{\"sources\":[99,0]}")])
        XCTAssertNil(ToolRouter.sourceIndexes(from: data, count: 2))
    }

    func testTheKeepingToolStillRequiresTheSourceNumbers() throws {
        let tool = try XCTUnwrap(ToolRouter.sourceFilterTools().first)
        let function = try XCTUnwrap(tool["function"] as? [String: Any])
        XCTAssertEqual(function["name"] as? String, ToolRouter.keepSourcesTool)
        let parameters = try XCTUnwrap(function["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["required"] as? [String], ["sources"])
        let properties = try XCTUnwrap(parameters["properties"] as? [String: Any])
        let description = try XCTUnwrap((properties["sources"] as? [String: Any])?["description"] as? String)
        XCTAssertFalse(description.isEmpty)
        XCTAssertFalse(description.contains("{{"))
    }
}
