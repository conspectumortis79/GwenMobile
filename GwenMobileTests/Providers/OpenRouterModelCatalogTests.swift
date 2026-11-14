@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class OpenRouterModelCatalogTests: XCTestCase {
    private let payload = Data("""
    {"data":[
      {"id":"openai/gpt-4o-mini","architecture":{"input_modalities":["text","image","file"],"output_modalities":["text"]},"supported_parameters":["max_tokens"]},
      {"id":"minimax/minimax-m3","architecture":{"input_modalities":["text","image","video"]},"reasoning":{"mandatory":false}},
      {"id":"google/gemini-3.5-flash","architecture":{"input_modalities":["text"]},"reasoning":{"supported_efforts":["high","medium","low","minimal"],"default_effort":"medium","default_enabled":true,"mandatory":true}},
      {"id":"openai/gpt-5.1","architecture":{"input_modalities":["image","text"]},"reasoning":{"supported_efforts":["xhigh","high","medium","low","none"],"mandatory":false}},
      {"id":"router/all","reasoning":{"supported_efforts":null,"mandatory":false}},
      {"id":"router/mandatory-all","reasoning":{"supported_efforts":null,"mandatory":true}},
      {"id":"odd/vendor","reasoning":{"supported_efforts":["ultra","high"],"mandatory":false}}
    ]}
    """.utf8)

    private func entries() throws -> [OpenRouterModelEntry] {
        try JSONDecoder().decode(OpenRouterModelList.self, from: payload).data
    }

    func testVideoInputComesFromTheArchitectureModalities() throws {
        let list = try entries()
        let video = list.first { $0.id == "minimax/minimax-m3" }
        XCTAssertEqual(OpenRouterModelCatalog.video(of: video?.architecture), .supported)
        let imageOnly = list.first { $0.id == "openai/gpt-4o-mini" }
        XCTAssertEqual(OpenRouterModelCatalog.video(of: imageOnly?.architecture), .rejected)
        XCTAssertEqual(OpenRouterModelCatalog.video(of: nil), .unknown)
        XCTAssertEqual(OpenRouterModelCatalog.capabilities(of: try XCTUnwrap(video)).video, .supported)
    }

    func testDecodingDistinguishesNullListedAndOmittedEfforts() throws {
        let list = try entries()
        let omitted = list.first { $0.id == "minimax/minimax-m3" }?.reasoning
        XCTAssertEqual(omitted?.effortsListed, false)
        XCTAssertNil(omitted?.supportedEfforts)
        let null = list.first { $0.id == "router/all" }?.reasoning
        XCTAssertEqual(null?.effortsListed, true)
        XCTAssertNil(null?.supportedEfforts)
        let listed = list.first { $0.id == "openai/gpt-5.1" }?.reasoning
        XCTAssertEqual(listed?.supportedEfforts, ["xhigh", "high", "medium", "low", "none"])
        XCTAssertNil(list.first { $0.id == "openai/gpt-4o-mini" }?.reasoning)
    }

    func testModelsWithoutReasoningOfferNoControlButAreKnown() throws {
        let caps = OpenRouterModelCatalog.capabilities(of: try entries()[0])
        XCTAssertTrue(caps.thinking.isKnown)
        XCTAssertFalse(caps.thinking.offersControl)
        XCTAssertEqual(caps.thinking.encoding, .openRouter)
        XCTAssertEqual(caps.thinking.directive(for: .medium), .nothing)
        XCTAssertEqual(caps.vision, .supported)
        XCTAssertTrue(caps.isCurrent(for: .openRouter))
    }

    func testOmittedEffortsCanOnlyBeSwitchedOff() throws {
        let caps = OpenRouterModelCatalog.capabilities(of: try entries()[1])
        XCTAssertEqual(caps.thinking.offeredLevels, [.modelDefault, .off])
        XCTAssertEqual(caps.thinking.directive(for: .off).bodyEntries["reasoning"] as? [String: Bool], ["enabled": false])
        XCTAssertEqual(caps.thinking.directive(for: .high), .nothing)
    }

    func testMandatoryModelsNeverOfferOff() throws {
        let gemini = OpenRouterModelCatalog.capabilities(of: try entries()[2]).thinking
        XCTAssertEqual(gemini.offeredLevels, [.modelDefault, .minimal, .low, .medium, .high])
        XCTAssertEqual(gemini.directive(for: .off), .nothing)
        XCTAssertEqual(gemini.directive(for: .low), .effort(.low, .openRouter))
        let mandatoryAll = OpenRouterModelCatalog.capabilities(of: try entries()[5]).thinking
        XCTAssertFalse(mandatoryAll.levels.contains(.off))
        XCTAssertEqual(mandatoryAll.directive(for: .off), .nothing)
    }

    func testListedNoneSwitchesOffViaEffortAndNullMeansEveryGatewayLevel() throws {
        let gpt = OpenRouterModelCatalog.capabilities(of: try entries()[3]).thinking
        XCTAssertEqual(gpt.directive(for: .off).bodyEntries["reasoning"] as? [String: String], ["effort": "none"])
        XCTAssertEqual(gpt.offeredLevels, [.modelDefault, .off, .low, .medium, .high, .xhigh])
        let all = OpenRouterModelCatalog.capabilities(of: try entries()[4]).thinking
        XCTAssertEqual(Set(all.levels), Set(ThinkingCapabilities.gatewayLevels))
        XCTAssertEqual(all.directive(for: .max), .effort(.max, .openRouter))
    }

    func testUnknownEffortNamesAreIgnored() throws {
        let odd = OpenRouterModelCatalog.capabilities(of: try entries()[6]).thinking
        XCTAssertEqual(odd.levels, [.high])
        XCTAssertEqual(odd.offeredLevels, [.modelDefault, .off, .high])
    }

    func testVisionFollowsTheInputModalities() throws {
        let list = try entries()
        XCTAssertEqual(OpenRouterModelCatalog.capabilities(of: list[2]).vision, .rejected)
        XCTAssertEqual(OpenRouterModelCatalog.capabilities(of: list[3]).vision, .supported)
        XCTAssertEqual(OpenRouterModelCatalog.capabilities(of: list[4]).vision, .rejected)
    }

    func testOnlyRequestedModelsAreReturned() throws {
        let found = OpenRouterModelCatalog.capabilities(of: try entries(), for: ["openai/gpt-5.1", "nicht/da"])
        XCTAssertEqual(Array(found.keys), ["openai/gpt-5.1"])
    }
}
