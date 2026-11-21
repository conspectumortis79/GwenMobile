@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class SettingsSeedTests: XCTestCase {
    func testSeedDecodesProviderConnectionsAndKeys() throws {
        let json = #"{"provider":"openai","openAICompatible":{"preset":"ollama","baseURL":"http://mortis.local:11434/v1"},"keys":{"openai":""}}"#
        let url = tempDocuments().appendingPathComponent("seed_provider.json")
        try Data(json.utf8).write(to: url)
        let seed = SettingsSeed.load(from: url)
        XCTAssertEqual(seed?.provider, .openAICompatible)
        XCTAssertEqual(seed?.openAICompatible?.baseURL, "http://mortis.local:11434/v1")
        XCTAssertEqual(seed?.openAICompatible?.preset, "ollama")
        XCTAssertEqual(seed?.keys, [.openAICompatible: ""])
        XCTAssertNil(seed?.qwenCloud)
        SettingsSeed.consume(url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testSeedOnlyOverridesTheConnectionsItNames() {
        var current = ProviderConnections()
        current.qwenCloud = QwenCloudConfig(billing: .payAsYouGo, region: .us)
        current.openRouter.appName = "Bestand"
        let seed = ProviderSeed(provider: nil, qwenCloud: nil,
                                openAICompatible: OpenAICompatibleConfig(customURL: "http://192.168.178.23:11434/v1"),
                                openRouter: nil, keys: nil)
        let merged = seed.applied(to: current)
        XCTAssertEqual(merged.qwenCloud, current.qwenCloud)
        XCTAssertEqual(merged.openRouter.appName, "Bestand")
        XCTAssertEqual(merged.openAICompatible.baseURL, "http://192.168.178.23:11434/v1")
        XCTAssertEqual(merged.openAICompatible.preset, "custom")
    }

    func testMissingOrBrokenSeedIsIgnored() throws {
        let dir = tempDocuments()
        XCTAssertNil(SettingsSeed.load(from: dir.appendingPathComponent("fehlt.json")))
        let broken = dir.appendingPathComponent("kaputt.json")
        try Data("nicht json".utf8).write(to: broken)
        XCTAssertNil(SettingsSeed.load(from: broken))
    }
}
