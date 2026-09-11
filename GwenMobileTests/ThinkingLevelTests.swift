import XCTest
@testable import GwenMobile

final class ThinkingLevelTests: XCTestCase {
    private let flashLevels: [ThinkingLevel] = [.off, .minimal, .low, .medium, .high, .xhigh, .max]
    private let proLevels: [ThinkingLevel] = [.low, .medium, .high, .xhigh, .max]

    private func decodedBody(_ req: URLRequest) -> [String: Any]? {
        guard let data = req.httpBody else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    func testRawValuesMatchTheProviderVocabulary() {
        XCTAssertEqual(ThinkingLevel.off.rawValue, "none")
        XCTAssertEqual(ThinkingLevel.modelDefault.rawValue, "default")
        XCTAssertEqual(ThinkingLevel(rawValue: "none"), .off)
        XCTAssertEqual(ThinkingLevel(rawValue: "xhigh"), .xhigh)
        XCTAssertNil(ThinkingLevel(rawValue: "ultra"))
    }

    func testModelDefaultSendsNothingAtAll() {
        let caps = ThinkingCapabilities(levels: flashLevels, canSwitchOff: true)
        XCTAssertEqual(caps.directive(for: .modelDefault), .nothing)
        XCTAssertTrue(caps.supports(.modelDefault))
        XCTAssertTrue(caps.directive(for: .modelDefault).bodyEntries.isEmpty)
    }

    func testEveryConfirmedLevelBecomesItsOwnEffortValue() {
        let caps = ThinkingCapabilities(levels: flashLevels, canSwitchOff: true)
        for level in flashLevels {
            XCTAssertEqual(caps.directive(for: level), .effort(level))
            XCTAssertEqual(caps.directive(for: level).bodyEntries["reasoning_effort"] as? String, level.rawValue)
        }
    }

    func testSwitchOffFallsBackToEnableThinkingWhenTheModelLacksNone() {
        let pro = ThinkingCapabilities(levels: proLevels, canSwitchOff: true)
        XCTAssertEqual(pro.directive(for: .off), .suppressThinking)
        XCTAssertEqual(pro.directive(for: .off).bodyEntries["enable_thinking"] as? Bool, false)
        XCTAssertTrue(pro.supports(.off))
    }

    func testLevelCannotBeSentWhenTheModelOffersNeitherWay() {
        let stubborn = ThinkingCapabilities(levels: proLevels, canSwitchOff: false)
        XCTAssertEqual(stubborn.directive(for: .off), .nothing)
        XCTAssertFalse(stubborn.supports(.off))
    }

    func testUnprobedModelStillAllowsTheCoreLevels() {
        let caps = ThinkingCapabilities.unknown
        XCTAssertFalse(caps.isKnown)
        for level in ThinkingLevel.coreCases {
            XCTAssertEqual(caps.directive(for: level), .effort(level))
        }
        XCTAssertEqual(caps.directive(for: .off), .nothing)
        XCTAssertEqual(caps.directive(for: .minimal), .nothing)
        XCTAssertEqual(caps.directive(for: .max), .nothing)
    }

    func testOfferedLevelsKeepProviderOrderAndNeverOfferUnsupportedOnes() {
        let pro = ThinkingCapabilities(levels: proLevels, canSwitchOff: true)
        XCTAssertEqual(pro.offeredLevels, [.modelDefault, .off] + proLevels)
        XCTAssertEqual(ThinkingCapabilities.unknown.offeredLevels,
                       [.modelDefault] + ThinkingLevel.coreCases)
        let rich = ThinkingCapabilities(levels: flashLevels, canSwitchOff: true)
        XCTAssertEqual(rich.offeredLevels, [.modelDefault] + flashLevels)
    }

    func testNeverBothThinkingKeysInOneBody() {
        let lists: [[ThinkingLevel]] = [flashLevels, proLevels, []]
        for list in lists {
            for switchable in [true, false] {
                let caps = ThinkingCapabilities(levels: list, canSwitchOff: switchable)
                for level in ThinkingLevel.allCases {
                    let entries = caps.directive(for: level).bodyEntries
                    XCTAssertFalse(entries.keys.contains("reasoning_effort")
                                   && entries.keys.contains("enable_thinking"),
                                   "beide Schlüssel gleichzeitig lehnt der Provider ab")
                    XCTAssertLessThanOrEqual(entries.count, 1)
                }
            }
        }
    }

    func testCapabilitiesSurviveTheSettingsRoundTrip() throws {
        let caps = ThinkingCapabilities(levels: flashLevels, canSwitchOff: true)
        let data = try JSONEncoder().encode([String: ThinkingCapabilities](uniqueKeysWithValues: [("qwen3.8-flash", caps)]))
        let back = try JSONDecoder().decode([String: ThinkingCapabilities].self, from: data)
        XCTAssertEqual(back["qwen3.8-flash"], caps)
    }

    func testDirectiveIsAppliedWithoutTouchingTheOtherBodyKeys() {
        var body: [String: Any] = ["model": "qwen3.8-flash", "stream": true]
        ThinkingDirective.effort(.medium).applied(to: &body)
        XCTAssertEqual(body["reasoning_effort"] as? String, "medium")
        XCTAssertEqual(body["model"] as? String, "qwen3.8-flash")
        XCTAssertEqual(body["stream"] as? Bool, true)
        ThinkingDirective.nothing.applied(to: &body)
        XCTAssertEqual(body.count, 3)
    }
}
