@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class ToolDecisionFallbackTests: GwenTestCase {
    func testAToolCallWithoutAFunctionIsIgnored() {
        let data = payload([["id": "c1", "type": "function"]])
        XCTAssertTrue(ToolRouter.decisions(from: data).isEmpty)
    }

    func testAToolCallWithoutArgumentsUsesTheEmptyBody() {
        let data = payload([["id": "c1", "type": "function", "function": ["name": ToolRouter.answerTool]]])
        XCTAssertEqual(ToolRouter.decisions(from: data).first?.route, .chat)
    }

    func testPlaceToolsWithoutWordsStillBuildEmptyRequests() throws {
        let near = try XCTUnwrap(ToolRouter.map(name: ToolRouter.placeTool, arguments: "{}"))
        guard case .nearbyPlace(let nearTerms, _) = near.route else { return XCTFail("kein Ort") }
        XCTAssertTrue(nearTerms.isEmpty)
        let route = try XCTUnwrap(ToolRouter.map(name: ToolRouter.routeTool, arguments: "{}"))
        guard case .routeToPlace(let routeTerms, _) = route.route else { return XCTFail("keine Route") }
        XCTAssertTrue(routeTerms.isEmpty)
    }

    func testTranslationWithoutATargetUsesTheFallbackTarget() throws {
        let decision = try XCTUnwrap(ToolRouter.map(name: ToolRouter.translateTool,
                                                    arguments: #"{"text":"Hello"}"#))
        guard case .translate(let job) = decision.route else { return XCTFail("kein Auftrag") }
        XCTAssertEqual(job.targetCode, TranslationLanguages.fallbackTarget)
    }

    func testPriceWatchWithoutWordsOrKeyHasNoRequest() {
        XCTAssertEqual(ToolRouter.map(name: ToolRouter.watchPriceTool,
                                      arguments: #"{"action":"delete"}"#)?.route, .chat)
    }

    func testMemoryReplaceAndEmptyTextAreHandled() throws {
        let replaced = try XCTUnwrap(ToolRouter.map(name: ToolRouter.memoryTool,
            arguments: ##"{"action":"create","text":"Fleisch","replace":"#ABCD1234"}"##))
        guard case .memory(let request) = replaced.route else { return XCTFail("kein Gedächtnisauftrag") }
        XCTAssertEqual(request.replaceKey, "abcd1234")
        XCTAssertEqual(ToolRouter.map(name: ToolRouter.memoryTool,
                                      arguments: #"{"action":"create","text":""}"#)?.route, .chat)
    }
}
