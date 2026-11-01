@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class PriceWatchRoutingTests: GwenTestCase {
    func testTheWatchToolIsOffered() {
        XCTAssertTrue(ToolSchemaNames.of(ToolRouter.tools(attachable: false)).contains(ToolRouter.watchPriceTool))
    }

    func testTheWatchToolNamesItsActionsAndTheCatalogKey() throws {
        let description = try toolDescription(ToolRouter.watchPriceTool)
        XCTAssertTrue(description.contains("compare_prices"), description)
        XCTAssertTrue(description.contains("PRICE WATCH CATALOG"), description)
        XCTAssertTrue(description.contains("one-off price question"), description)
        let properties = try toolProperties(ToolRouter.watchPriceTool)
        XCTAssertNotNil(properties["terms"])
        XCTAssertNotNil(properties["goal"])
        XCTAssertNotNil(properties["intervalHours"])
        XCTAssertNotNil(properties["key"])
        let action = try XCTUnwrap(properties["action"] as? [String: Any])
        XCTAssertEqual(Set(action["enum"] as? [String] ?? []),
                       ["create", "update", "delete", "check", "list"])
    }

    func testACreateCallBecomesAWatchRequest() throws {
        let decision = try XCTUnwrap(ToolRouter.decisions(from: call(ToolRouter.watchPriceTool,
                                                                    ["action": "create",
                                                                     "terms": ["PlayStation 5", "PS5"],
                                                                     "goal": 400,
                                                                     "country": "DE"])).first)
        guard case .priceWatch(let request) = decision.route else {
            return XCTFail("watch_price landete nicht im Preis-Wecker: \(decision.route)")
        }
        XCTAssertEqual(request.action, .create)
        XCTAssertEqual(request.terms, ["PlayStation 5", "PS5"])
        XCTAssertEqual(request.goal, 400)
        XCTAssertEqual(request.country, "DE")
        XCTAssertNil(request.intervalHours)
        XCTAssertEqual(decision.stepKind, .priceWatch)
    }

    func testAGoalWrittenAsAStringIsStillUnderstood() throws {
        let decision = try XCTUnwrap(ToolRouter.decisions(from: call(ToolRouter.watchPriceTool,
                                                                    ["action": "create",
                                                                     "terms": ["Kopfhörer Aura X"],
                                                                     "goal": "199,00"])).first)
        guard case .priceWatch(let request) = decision.route else { return XCTFail("kein Wecker") }
        XCTAssertEqual(request.goal, 199)
    }

    func testUpdateDeleteAndCheckFindTheWatchByKey() throws {
        let update = try XCTUnwrap(ToolRouter.decisions(from: call(ToolRouter.watchPriceTool,
                                                                  ["action": "update", "key": "#AbCd1234",
                                                                   "goal": 350, "intervalHours": 12])).first)
        guard case .priceWatch(let updated) = update.route else { return XCTFail("kein update") }
        XCTAssertEqual(updated.action, .update)
        XCTAssertEqual(updated.key, "abcd1234")
        XCTAssertEqual(updated.goal, 350)
        XCTAssertEqual(updated.intervalHours, 12)

        let delete = try XCTUnwrap(ToolRouter.decisions(from: call(ToolRouter.watchPriceTool,
                                                                  ["action": "delete", "key": "abcd1234"])).first)
        guard case .priceWatch(let deleted) = delete.route else { return XCTFail("kein delete") }
        XCTAssertEqual(deleted.action, .delete)

        let check = try XCTUnwrap(ToolRouter.decisions(from: call(ToolRouter.watchPriceTool,
                                                                 ["action": "check",
                                                                  "terms": ["PlayStation 5"]])).first)
        guard case .priceWatch(let checked) = check.route else { return XCTFail("kein check") }
        XCTAssertEqual(checked.action, .check)
        XCTAssertEqual(checked.terms, ["PlayStation 5"])
    }

    func testListNeedsNothingElse() throws {
        let decision = try XCTUnwrap(ToolRouter.decisions(from: call(ToolRouter.watchPriceTool,
                                                                    ["action": "list"])).first)
        guard case .priceWatch(let request) = decision.route else { return XCTFail("keine Liste") }
        XCTAssertEqual(request.action, .list)
    }

    func testACreateWithoutProductOrGoalStaysAChat() throws {
        let noTerms = try XCTUnwrap(ToolRouter.decisions(from: call(ToolRouter.watchPriceTool,
                                                                   ["action": "create", "goal": 400])).first)
        XCTAssertEqual(noTerms.stepKind, .chat)
        let noGoal = try XCTUnwrap(ToolRouter.decisions(from: call(ToolRouter.watchPriceTool,
                                                                  ["action": "create",
                                                                   "terms": ["PlayStation 5"]])).first)
        XCTAssertEqual(noGoal.stepKind, .chat)
        let broken = try XCTUnwrap(ToolRouter.decisions(from: call(ToolRouter.watchPriceTool,
                                                                  ["action": "dance"])).first)
        XCTAssertEqual(broken.stepKind, .chat)
    }

    func testAnUpdateWithoutAChangeStaysAChat() throws {
        let onlyKey = try XCTUnwrap(ToolRouter.decisions(from: call(ToolRouter.watchPriceTool,
                                                                   ["action": "update", "key": "abcd1234"])).first)
        XCTAssertEqual(onlyKey.stepKind, .chat)
    }

    func testTheWatchStepDoesNotMergeIntoAnotherAnswer() throws {
        let watch = try XCTUnwrap(ToolRouter.map(name: ToolRouter.watchPriceTool,
                                                 arguments: #"{"action":"create","terms":["PlayStation 5"],"goal":400}"#))
        let answer = try XCTUnwrap(ToolRouter.map(name: ToolRouter.answerTool, arguments: "{}"))
        let plan = SendPlan.forming([watch, answer])
        XCTAssertEqual(plan.actions.count, 2)
        XCTAssertFalse(plan.merges)
    }

    func testTheSystemBlockCarriesTheWatchCatalog() {
        let block = ToolRouter.systemBlock(now: "x", context: SendContext(), transcript: "",
                                           watchCatalog: "[#abcd1234] PlayStation 5 (goal 400.00 EUR, waiting)")
        XCTAssertTrue(block.contains("PRICE WATCH CATALOG"), block)
        XCTAssertTrue(block.contains("[#abcd1234] PlayStation 5"), block)
        XCTAssertFalse(block.contains("{{"), block)
    }

    func testTheSystemBlockNamesTheWatchTool() {
        let block = ToolRouter.systemBlock(now: "x", context: SendContext(), transcript: "")
        XCTAssertTrue(block.contains(ToolRouter.watchPriceTool), block)
        XCTAssertTrue(block.contains("target price"), block)
    }

    func testTwoSplitsOfOneWatchWishBecomeOneWatch() throws {
        let first = try XCTUnwrap(ToolRouter.map(name: ToolRouter.watchPriceTool,
            arguments: #"{"action":"create","terms":["Mac Studio M5 Ultra 30C/64C 256 GB"],"goal":10000}"#))
        let second = try XCTUnwrap(ToolRouter.map(name: ToolRouter.watchPriceTool,
            arguments: #"{"action":"create","terms":["Mac Studio M5 Ultra 30C/64C 1 TB"],"goal":10000}"#))
        let plan = SendPlan.forming([first, second])
        XCTAssertEqual(plan.actions.count, 1, "ein Satz darf nicht zwei Wecker anlegen")
        guard case .priceWatch(let request) = plan.primary.route else { return XCTFail("kein Wecker") }
        XCTAssertEqual(request.terms, ["Mac Studio M5 Ultra 30C/64C 256 GB",
                                       "Mac Studio M5 Ultra 30C/64C 1 TB"])
        XCTAssertEqual(request.goal, 10000)
    }

    func testTwoDifferentProductsWithTheSameGoalStayTwoWatches() throws {
        let first = try XCTUnwrap(ToolRouter.map(name: ToolRouter.watchPriceTool,
            arguments: #"{"action":"create","terms":["PlayStation 5"],"goal":400}"#))
        let second = try XCTUnwrap(ToolRouter.map(name: ToolRouter.watchPriceTool,
            arguments: #"{"action":"create","terms":["Kopfhörer Aura X"],"goal":400}"#))
        let plan = SendPlan.forming([first, second])
        XCTAssertEqual(plan.actions.count, 2)
    }

    func testTwoGoalsForOneProductStayTwoWatches() throws {
        let first = try XCTUnwrap(ToolRouter.map(name: ToolRouter.watchPriceTool,
            arguments: #"{"action":"create","terms":["PlayStation 5"],"goal":400}"#))
        let second = try XCTUnwrap(ToolRouter.map(name: ToolRouter.watchPriceTool,
            arguments: #"{"action":"create","terms":["PlayStation 5"],"goal":300}"#))
        let plan = SendPlan.forming([first, second])
        XCTAssertEqual(plan.actions.count, 2)
    }
}
