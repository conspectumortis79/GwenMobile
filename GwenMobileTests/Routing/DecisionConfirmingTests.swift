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
}
