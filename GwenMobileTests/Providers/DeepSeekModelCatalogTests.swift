@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class DeepSeekModelCatalogTests: XCTestCase {
    private let payload = Data("""
    {"object":"list","data":[
      {"id":"deepseek-flash","object":"model","owned_by":"deepseek","name":"DeepSeek-V4.1-Flash",
       "context_window":1048576,"max_output_tokens":393216,
       "input_modalities":["text","image"],"output_modalities":["text"],
       "effort":{"supported_levels":["low","high","max"],"default_level":"high"}},
      {"id":"deepseek-v4-pro","object":"model","input_modalities":["text"],
       "effort":{"supported_levels":["high","max"],"default_level":"high"}},
      {"id":"deepseek-without-effort","input_modalities":["text"]},
      {"id":"deepseek-flat","input_modalities":["text"],
       "supported_levels":["medium"],"default_level":"medium"},
      {"id":"deepseek-odd","input_modalities":["audio"],
       "effort":{"supported_levels":["ultra","low"]}}
    ]}
    """.utf8)

    private func entries() throws -> [DeepSeekModelEntry] {
        try JSONDecoder().decode(DeepSeekModelList.self, from: payload).data
    }

    func testDecodingReadsModalitiesAndNestedEffortMetadata() throws {
        let list = try entries()
        XCTAssertEqual(list[0].id, "deepseek-flash")
        XCTAssertEqual(list[0].inputModalities, ["text", "image"])
        XCTAssertEqual(list[0].effort?.supportedLevels, ["low", "high", "max"])
        XCTAssertNil(list[2].effort)
    }

    func testFlatEffortMetadataIsReadAsAFallback() throws {
        let flat = try entries()[3]
        XCTAssertEqual(flat.effort?.supportedLevels, ["medium"])
    }

    func testThinkingOffersTheConfirmedLevelsAndSwitchesOffWithNone() throws {
        let flash = DeepSeekModelCatalog.capabilities(of: try entries()[0]).thinking
        XCTAssertTrue(flash.probed)
        XCTAssertEqual(flash.encoding, .openAI)
        XCTAssertEqual(flash.offeredLevels, [.modelDefault, .off, .low, .high, .max])
        XCTAssertEqual(flash.directive(for: .off).bodyEntries["reasoning_effort"] as? String, "none")
        XCTAssertEqual(flash.directive(for: .high).bodyEntries["reasoning_effort"] as? String, "high")
        XCTAssertEqual(flash.directive(for: .minimal), .nothing)
    }

    func testUnknownEffortNamesAreIgnored() throws {
        let odd = DeepSeekModelCatalog.capabilities(of: try entries()[4]).thinking
        XCTAssertEqual(odd.levels, [.low])
        XCTAssertEqual(odd.offeredLevels, [.modelDefault, .off, .low])
    }

    func testMissingEffortMetadataStaysKnownButOffersOnlyTheDefault() throws {
        let legacy = DeepSeekModelCatalog.capabilities(of: try entries()[2]).thinking
        XCTAssertTrue(legacy.isKnown)
        XCTAssertFalse(legacy.offersControl)
        XCTAssertEqual(legacy.offeredLevels, [.modelDefault])
        XCTAssertEqual(legacy.directive(for: .off), .nothing)
        XCTAssertEqual(legacy.directive(for: .high), .nothing)
    }

    func testVisionFollowsTheInputModalities() throws {
        let list = try entries()
        XCTAssertEqual(DeepSeekModelCatalog.capabilities(of: list[0]).vision, .supported)
        XCTAssertEqual(DeepSeekModelCatalog.capabilities(of: list[1]).vision, .rejected)
        XCTAssertEqual(DeepSeekModelCatalog.capabilities(of: list[4]).vision, .rejected)
    }

    func testCapabilitiesAreCompleteAndCurrentForTheOpenAIEncoding() throws {
        let caps = DeepSeekModelCatalog.capabilities(of: try entries()[0])
        XCTAssertTrue(caps.isComplete)
        XCTAssertTrue(caps.isCurrent(for: .openAI))
        XCTAssertFalse(caps.isCurrent(for: .dashScope))
        XCTAssertFalse(caps.isCurrent(for: .openRouter))
    }

    func testOnlyRequestedModelsAreReturned() throws {
        let found = DeepSeekModelCatalog.capabilities(of: try entries(),
                                                      for: ["deepseek-v4-pro", "nicht/da"])
        XCTAssertEqual(Array(found.keys), ["deepseek-v4-pro"])
    }
}
