@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class DecisionConfirmingTests: GwenTestCase {
    func testTheNearbyCheckAsksAgainWhenTheTermsMissTheWish() async {
        let first = ToolDecision(route: .nearbyPlace(terms: ["mediamarkt"], mode: .walking))
        let fresh = ToolDecision(route: .nearbyPlace(terms: ["bauhaus rosenheim"], mode: .walking))
        let asked = LockedValue<[String]>([])
        let checked = await NearbyWishCheck().checked(first, wish: "bauhaus rosenheim") { hint in
            asked.mutate { $0.append(hint) }
            return fresh
        }
        XCTAssertEqual(asked.current.count, 1)
        XCTAssertFalse(asked.current[0].isEmpty)
        XCTAssertEqual(checked.route, fresh.route)
    }

    func testAFindDecisionIsCheckedAndCanBecomeCreate() async {
        let first = ToolDecision(route: .pictureSearch(query: "Cary Elwes als Pirat"))
        let fresh = ToolDecision(route: .imageCreate, picturePrompt: "Cary Elwes als Pirat")
        let asked = LockedValue<[String]>([])
        let checked = await PictureIntentCheck().checked(first, wish: "male cary elwes als pirat") { hint in
            asked.mutate { $0.append(hint) }
            return fresh
        }
        XCTAssertEqual(asked.current.count, 1)
        XCTAssertTrue(asked.current[0].contains("create_picture"))
        XCTAssertEqual(checked.route, .imageCreate)
    }

    func testAFindDecisionStaysFindWhenTheCheckConfirmsIt() async {
        let first = ToolDecision(route: .pictureSearch(query: "Nordlicht"))
        let checked = await PictureIntentCheck().checked(first, wish: "zeig mir fotos vom nordlicht") { _ in
            ToolDecision(route: .pictureSearch(query: "Nordlicht"))
        }
        XCTAssertEqual(checked.route, first.route)
    }

    func testAFindDecisionWithoutAFreshAnswerKeepsTheFirst() async {
        let first = ToolDecision(route: .pictureSearch(query: "Nordlicht"))
        let checked = await PictureIntentCheck().checked(first, wish: "zeig mir fotos vom nordlicht") { _ in nil }
        XCTAssertEqual(checked.route, first.route)
    }

    func testAPlainChatCanBecomeAPriceComparison() async {
        let first = ToolDecision(route: .chat)
        let fresh = ToolDecision(route: .priceSearch(terms: ["Kaffeevollautomat"], country: "PL", nearby: false))
        let asked = LockedValue<[String]>([])
        let checked = await PriceIntentCheck().checked(first, wish: "gibt es den Kaffeevollautomaten in Polen günstiger?") { hint in
            asked.mutate { $0.append(hint) }
            return fresh
        }
        XCTAssertEqual(asked.current.count, 1)
        XCTAssertFalse(asked.current[0].isEmpty)
        XCTAssertEqual(checked.route, fresh.route)
    }

    func testAPriceCheckKeepsChatWhenTheFreshAnswerStaysChat() async {
        let first = ToolDecision(route: .chat)
        let checked = await PriceIntentCheck().checked(first, wish: "erzähl mir etwas") { _ in
            ToolDecision(route: .chat)
        }
        XCTAssertEqual(checked.route, first.route)
    }

    func testThePictureDuplicateCheckMergesOnlyWhenTheModelAgrees() async {
        let first = ToolDecision(route: .imageCreate, picturePrompt: "Mona Lisa in Farbe")
        let second = ToolDecision(route: .imageCreate, picturePrompt: "Ein Farbbild der Mona Lisa")
        let merged = await PictureWishMerge.merged([first, second]) { _, _ in true }
        XCTAssertEqual(merged.count, 1)
        let separate = await PictureWishMerge.merged([first, second]) { _, _ in false }
        XCTAssertEqual(separate.count, 2)
        let unchanged = await PictureWishMerge.merged([ToolDecision(route: .chat), second]) { _, _ in true }
        XCTAssertEqual(unchanged.count, 2)
        XCTAssertTrue(PictureWishMerge.same("SAME"))
        XCTAssertTrue(PictureWishMerge.same("They are the same picture."))
        XCTAssertFalse(PictureWishMerge.same("DIFFERENT"))
        XCTAssertFalse(PictureWishMerge.same("NOT SAME"))
        XCTAssertFalse(PictureWishMerge.same("not the same"))
        XCTAssertFalse(PictureWishMerge.same("no, same"))
        XCTAssertFalse(PictureWishMerge.same("it isn't the same"))
        XCTAssertFalse(PictureWishMerge.same("it isn’t the same"))
        XCTAssertFalse(PictureWishMerge.same("same or different"))
        XCTAssertFalse(PictureWishMerge.same(nil))
    }

    func testAPriceCheckDoesNotAskARealActionAgain() async {
        let first = ToolDecision(route: .nearbyPlace(terms: ["REWE"], mode: .automatic))
        let asked = LockedValue(0)
        let checked = await PriceIntentCheck().checked(first, wish: "wo ist der nächste REWE?") { _ in
            asked.mutate { $0 += 1 }
            return first
        }
        XCTAssertEqual(asked.current, 0)
        XCTAssertEqual(checked.route, first.route)
    }

    func testACreateDecisionIsNeverAskedAgain() async {
        let first = ToolDecision(route: .imageCreate, picturePrompt: "Mona Lisa")
        let asked = LockedValue(0)
        let checked = await PictureIntentCheck().checked(first, wish: "zeichne die mona lisa") { _ in
            asked.mutate { $0 += 1 }
            return first
        }
        XCTAssertEqual(asked.current, 0)
        XCTAssertEqual(checked.route, first.route)
    }

    func testAShortTickOffCanBecomeComplete() async throws {
        let first = ToolDecision(route: .reminder(try XCTUnwrap(ReminderRequest(
            plan: ReminderPlan(action: .create, title: "Milch")))))
        let fresh = ToolDecision(route: .reminder(try XCTUnwrap(ReminderRequest(
            plan: ReminderPlan(action: .complete, find: "Milch")))))
        let asked = LockedValue(0)
        let checked = await ReminderActionCheck().checked(first, wish: "Hak Milch ab") { hint in
            asked.mutate { $0 += 1 }
            XCTAssertFalse(hint.isEmpty)
            return fresh
        }
        XCTAssertEqual(asked.current, 1)
        guard case .reminder(let request) = checked.route else {
            return XCTFail("keine Erinnerung")
        }
        XCTAssertEqual(request.action, .complete)
        XCTAssertEqual(request.find, "Milch")
    }

    func testALongReminderIsNeverAskedAgain() async throws {
        let first = ToolDecision(route: .reminder(try XCTUnwrap(ReminderRequest(
            plan: ReminderPlan(action: .create, title: "Zahnarzt")))))
        let asked = LockedValue(0)
        let checked = await ReminderActionCheck().checked(
            first, wish: "Erinnere mich morgen um 9 an den Zahnarzt") { _ in
                asked.mutate { $0 += 1 }
                return first
            }
        XCTAssertEqual(asked.current, 0)
        XCTAssertEqual(checked.route, first.route)
    }

    func testAShortCheckKeepsCreateWhenTheFreshAnswerStaysCreate() async throws {
        let first = ToolDecision(route: .reminder(try XCTUnwrap(ReminderRequest(
            plan: ReminderPlan(action: .create, title: "Milch")))))
        let checked = await ReminderActionCheck().checked(first, wish: "Hak Milch ab") { _ in
            first
        }
        XCTAssertEqual(checked.route, first.route)
    }

    func testAGroundedAnswerIsNeverAskedAgain() async {
        let first = ToolDecision(route: .nearbyPlace(terms: ["bauhaus rosenheim"], mode: .walking))
        let asked = LockedValue(0)
        let checked = await NearbyWishCheck().checked(first, wish: "bauhaus rosenheim") { _ in
            asked.mutate { $0 += 1 }
            return first
        }
        XCTAssertEqual(asked.current, 0)
        XCTAssertEqual(checked.route, first.route)
    }

func testThePictureDuplicateRequestCarriesTheTwoWishes() throws {
        let request = try PictureWishMerge.request(baseURL: "https://q.test/v1", key: "k", model: "m",
                                                   first: "Mona Lisa", second: "Lächeln",
                                                   thinking: .nothing)
        XCTAssertEqual(request.url?.path, "/v1/chat/completions")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody))
            as? [String: Any])
        XCTAssertEqual(body["max_tokens"] as? Int, 8)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertTrue((messages[1]["content"] as? String)?.contains("Mona Lisa") ?? false)
    }
}
