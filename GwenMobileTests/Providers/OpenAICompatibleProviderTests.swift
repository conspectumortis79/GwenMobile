@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class OpenAICompatibleProviderTests: XCTestCase {
    func testSelectingAPresetFillsItsURL() {
        var config = OpenAICompatibleConfig()
        config.select(presetID: "groq")
        XCTAssertEqual(config.preset, "groq")
        XCTAssertEqual(config.baseURL, "https://api.groq.com/openai/v1")
        config.select(presetID: "custom")
        XCTAssertEqual(config.preset, "custom")
        XCTAssertEqual(config.baseURL, "")
    }

    func testEditingTheURLSwitchesThePresetToTheMatchOrToCustom() {
        var config = OpenAICompatibleConfig()
        config.edit(baseURL: "https://my.server/v1")
        XCTAssertEqual(config.preset, "custom")
        config.edit(baseURL: "https://api.mistral.ai/v1/")
        XCTAssertEqual(config.preset, "mistral")
        XCTAssertEqual(config.baseURL, "https://api.mistral.ai/v1/")
    }

    func testCustomURLInitialiserDetectsPresets() {
        XCTAssertEqual(OpenAICompatibleConfig(customURL: "http://localhost:11434/v1").preset, "ollama")
        XCTAssertEqual(OpenAICompatibleConfig(customURL: "https://x.example/v1").preset, "custom")
    }

    func testUnknownPresetIDFallsBackToCustom() {
        XCTAssertEqual(OpenAIPresets.preset(id: "nope"), OpenAIPresets.custom)
        XCTAssertNil(OpenAIPresets.matching(url: ""))
        XCTAssertNil(OpenAIPresets.matching(url: "   "))
    }

    func testLocalPresetsMakeTheKeyOptional() {
        let descriptor = OpenAICompatibleDescriptor()
        var connections = ProviderConnections()
        connections.openAICompatible.select(presetID: "openai")
        XCTAssertFalse(descriptor.isConfigured(connections, key: ""))
        XCTAssertTrue(descriptor.isConfigured(connections, key: "sk-1"))
        XCTAssertEqual(descriptor.keyPlaceholder(connections), "sk-…")
        XCTAssertTrue(descriptor.usesPresetURL(connections))
        connections.openAICompatible.select(presetID: "lmstudio")
        XCTAssertTrue(descriptor.isConfigured(connections, key: ""))
        XCTAssertEqual(descriptor.keyPlaceholder(connections), L.t("key_optional_local"))
    }

    func testCustomServerNeedsAURLAndDoesNotAutoReload() {
        let descriptor = OpenAICompatibleDescriptor()
        var connections = ProviderConnections()
        connections.openAICompatible.select(presetID: "custom")
        XCTAssertFalse(descriptor.isConfigured(connections, key: "sk-1"))
        connections.openAICompatible.edit(baseURL: " https://x.example/v1 ")
        XCTAssertEqual(descriptor.baseURL(connections), "https://x.example/v1")
        XCTAssertTrue(descriptor.isConfigured(connections, key: "sk-1"))
        XCTAssertFalse(descriptor.usesPresetURL(connections))
    }

    func testCapabilitiesAreProbedExceptChat() {
        let caps = OpenAICompatibleDescriptor().capabilities
        XCTAssertEqual(caps.chat, .available)
        XCTAssertEqual(caps.vision, .probed)
        XCTAssertEqual(caps.image, .unavailable)
        XCTAssertNil(OpenAICompatibleDescriptor().imageBackend)
        XCTAssertNil(OpenAICompatibleDescriptor().consoleLink)
    }

    func testPresetLabelsUseTheAppLanguageWhereTheyAreNotBrandNames() {
        L.apply(.de)
        XCTAssertEqual(OpenAIPresets.custom.label, "Eigener Server")
        XCTAssertEqual(OpenAIPresets.preset(id: "openai").label, "OpenAI")
        L.apply(.en)
        XCTAssertEqual(OpenAIPresets.preset(id: "ollama").label, "Ollama (local)")
        L.apply(.en)
    }
}
