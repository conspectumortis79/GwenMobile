@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class ThinkingEncodingTests: XCTestCase {
    func testDashScopeKeepsTheQwenParameters() {
        XCTAssertEqual(ThinkingDirective.effort(.medium, .dashScope).bodyEntries["reasoning_effort"] as? String, "medium")
        XCTAssertEqual(ThinkingDirective.suppressing(.dashScope).bodyEntries["enable_thinking"] as? Bool, false)
    }

    func testOpenAIUsesReasoningEffortOnlyAndSwitchesOffWithNone() {
        XCTAssertEqual(ThinkingDirective.effort(.high, .openAI).bodyEntries["reasoning_effort"] as? String, "high")
        let off = ThinkingDirective.suppressing(.openAI).bodyEntries
        XCTAssertEqual(off["reasoning_effort"] as? String, "none")
        XCTAssertNil(off["enable_thinking"])
    }

    func testOpenRouterUsesTheUnifiedReasoningObject() {
        let effort = ThinkingDirective.effort(.low, .openRouter).bodyEntries["reasoning"] as? [String: Any]
        XCTAssertEqual(effort?["effort"] as? String, "low")
        let off = ThinkingDirective.suppressing(.openRouter).bodyEntries["reasoning"] as? [String: Any]
        XCTAssertEqual(off?["enabled"] as? Bool, false)
        XCTAssertNil(ThinkingDirective.effort(.low, .openRouter).bodyEntries["reasoning_effort"])
    }

    func testCapabilitiesCarryTheirEncodingIntoEveryDirective() {
        let router = ThinkingCapabilities(levels: [.low, .high], canSwitchOff: true, encoding: .openRouter, probed: true)
        XCTAssertEqual(router.directive(for: .high), .effort(.high, .openRouter))
        XCTAssertEqual(router.directive(for: .off), .suppressing(.openRouter))
        XCTAssertEqual(router.directive(for: .medium), .nothing)
        let openAI = ThinkingCapabilities(levels: [.off, .low], encoding: .openAI, probed: true)
        XCTAssertEqual(openAI.directive(for: .off), .effort(.off, .openAI))
    }

    func testAProbedModelWithoutLevelsOffersOnlyTheDefault() {
        let none = ThinkingCapabilities(encoding: .openAI, probed: true)
        XCTAssertTrue(none.isKnown)
        XCTAssertFalse(none.offersControl)
        XCTAssertEqual(none.offeredLevels, [.modelDefault])
        for level in ThinkingLevel.coreCases {
            XCTAssertEqual(none.directive(for: level), .nothing, "\(level)")
        }
    }

    func testAProbedModelThatOnlyTogglesOffersDefaultAndOff() {
        let toggle = ThinkingCapabilities(canSwitchOff: true, encoding: .openRouter, probed: true)
        XCTAssertEqual(toggle.offeredLevels, [.modelDefault, .off])
        XCTAssertEqual(toggle.directive(for: .off), .suppressing(.openRouter))
        XCTAssertEqual(toggle.directive(for: .medium), .nothing)
    }

    func testOldStoredCapabilitiesDecodeAsDashScopeAndUnprobed() throws {
        let legacy = Data(#"{"levels":["low","high"],"canSwitchOff":true}"#.utf8)
        let caps = try JSONDecoder().decode(ThinkingCapabilities.self, from: legacy)
        XCTAssertEqual(caps.encoding, .dashScope)
        XCTAssertFalse(caps.probed)
        XCTAssertEqual(caps.levels, [.low, .high])
        let roundTrip = ThinkingCapabilities(levels: [.medium], canSwitchOff: false, encoding: .openRouter, probed: true)
        let back = try JSONDecoder().decode(ThinkingCapabilities.self, from: JSONEncoder().encode(roundTrip))
        XCTAssertEqual(back, roundTrip)
    }

    func testStoredCapabilitiesOfAnotherEncodingAreNotCurrent() {
        let qwenStyle = ModelCapabilities(thinking: ThinkingCapabilities(levels: [.low], canSwitchOff: true), vision: .rejected)
        XCTAssertTrue(qwenStyle.isComplete)
        XCTAssertTrue(qwenStyle.isCurrent(for: .dashScope))
        XCTAssertFalse(qwenStyle.isCurrent(for: .openRouter))
        var profile = ProviderProfile(availableModels: ["a/b", "c/d"], modelCaps: ["a/b": qwenStyle])
        XCTAssertEqual(profile.modelsNeedingCaps(encoding: .openRouter), ["a/b", "c/d"])
        XCTAssertEqual(profile.modelsNeedingCaps(encoding: .dashScope), ["c/d"])
        profile.merge(caps: ["a/b": ModelCapabilities(thinking: ThinkingCapabilities(encoding: .openRouter, probed: true),
                                                     vision: .supported)])
        XCTAssertEqual(profile.modelsNeedingCaps(encoding: .openRouter), ["c/d"])
    }
}
