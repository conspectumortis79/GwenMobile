@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class MemoryRoutingTests: GwenTestCase {
    func testTheMemoryToolIsOffered() {
        let names = ToolSchemaNames.of(ToolRouter.tools(attachable: false))
        XCTAssertTrue(names.contains(ToolRouter.memoryTool))
    }

    func testTheAnswerToolCarriesMemoryKeys() throws {
        let properties = try toolProperties(ToolRouter.answerTool)
        XCTAssertNotNil(properties["memory"])
    }

    func testCreateMapsOntoTheMemoryRoute() throws {
        let decision = try XCTUnwrap(ToolRouter.decisions(
            from: call(ToolRouter.memoryTool, ["action": "create", "text": "Ich esse kein Fleisch",
                                               "category": "likes"])).first)
        guard case .memory(let request) = decision.route else {
            return XCTFail("create landete nicht im Gedächtnis: \(decision.route)")
        }
        XCTAssertEqual(request.action, .create)
        XCTAssertEqual(request.text, "Ich esse kein Fleisch")
        XCTAssertEqual(request.category, .likes)
        XCTAssertEqual(decision.stepKind, .memory)
    }

    func testSuggestAndForgetAndListMapOntoTheMemoryRoute() throws {
        let suggest = try XCTUnwrap(ToolRouter.decisions(
            from: call(ToolRouter.memoryTool, ["action": "suggest", "text": "Ich mag Ingwer-Tee",
                                               "category": "likes"])).first)
        guard case .memory(let suggested) = suggest.route else { return XCTFail("suggest fehlt") }
        XCTAssertEqual(suggested.action, .suggest)
        let forget = try XCTUnwrap(ToolRouter.decisions(
            from: call(ToolRouter.memoryTool, ["action": "forget", "key": "ABCD1234"])).first)
        guard case .memory(let forgotten) = forget.route else { return XCTFail("forget fehlt") }
        XCTAssertEqual(forgotten.action, .forget)
        XCTAssertEqual(forgotten.key, "abcd1234")
        let list = try XCTUnwrap(ToolRouter.decisions(
            from: call(ToolRouter.memoryTool, ["action": "list"])).first)
        guard case .memory(let listed) = list.route else { return XCTFail("list fehlt") }
        XCTAssertEqual(listed.action, .list)
    }

    func testAForgetWithoutAKeyFallsBackToChat() {
        let decision = ToolRouter.decisions(from: call(ToolRouter.memoryTool, ["action": "forget"])).first
        XCTAssertEqual(decision?.route, .chat)
    }

    func testABrokenMemoryCallFallsBackToChat() {
        let decision = ToolRouter.decisions(from: call(ToolRouter.memoryTool, ["action": "dance"])).first
        XCTAssertEqual(decision?.route, .chat)
    }

    func testTheAnswerCarriesTheChosenKeys() throws {
        let decision = try XCTUnwrap(ToolRouter.decisions(
            from: call(ToolRouter.answerTool, ["memory": ["#ABCD1234", "beef5678"]])).first)
        XCTAssertEqual(decision.memoryKeys, ["abcd1234", "beef5678"])
        XCTAssertEqual(decision.stepKind, .chat)
    }

    func testAMemoryStepDoesNotMergeSilentlyIntoAnotherAnswer() throws {
        let created = try XCTUnwrap(ToolRouter.map(name: ToolRouter.memoryTool,
                                                   arguments: #"{"action":"create","text":"Ich esse kein Fleisch","category":"likes"}"#))
        let forgotten = try XCTUnwrap(ToolRouter.map(name: ToolRouter.memoryTool,
                                                     arguments: #"{"action":"forget","key":"abcd1234"}"#))
        let plan = SendPlan.forming([created, forgotten])
        XCTAssertEqual(plan.actions.count, 2)
        XCTAssertFalse(plan.merges)
    }

    func testTheSystemBlockNamesTheCatalogWhenOneExists() {
        let block = ToolRouter.systemBlock(now: "2026-10-04 16:20", context: SendContext(),
                                           transcript: "",
                                           catalog: "[#abcd1234] Ich esse kein Fleisch (preference, pinned)")
        XCTAssertTrue(block.contains("MEMORY CATALOG"))
        XCTAssertTrue(block.contains("abcd1234"))
        XCTAssertTrue(block.contains(ToolRouter.memoryTool))
    }

    func testTheSystemBlockStaysCleanWithoutCatalog() {
        let block = ToolRouter.systemBlock(now: "2026-10-04 16:20", context: SendContext(), transcript: "")
        XCTAssertFalse(block.contains("MEMORY CATALOG"))
        XCTAssertTrue(block.contains(ToolRouter.memoryTool))
    }

    func testAnIsoDateIsAcceptedForAMemoryEntry() throws {
        let request = try XCTUnwrap(MemoryRequest.from(["action": "create", "text": "Urlaub",
                                                         "date": "2026-10-08T12:00:00Z"]))
        XCTAssertNotNil(request.date)
        let short = try XCTUnwrap(MemoryRequest.from(["action": "create", "text": "Urlaub",
                                                      "date": "2026-10-08"]))
        XCTAssertNotNil(short.date)
    }
}
