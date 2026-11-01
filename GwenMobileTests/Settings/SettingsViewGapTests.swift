@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit

private struct GapDiscoverer: ModelDiscovering {
    var found: [String: ModelCapabilities]

    func discover(baseURL: String, key: String, models: [String]) async -> [String: ModelCapabilities] {
        found
    }
}

@MainActor
final class SettingsViewGapTests: GwenTestCase {
    func testSmokeTheConnectionTestPaths() async throws {
        _ = stagedStoreWithCleaner("settings-connection")
        let view = SettingsView()
        let provider = AppSettings.shared.provider
        AppSettings.shared.setKey("gap-connection-key", for: provider)
        MockHTTP.install { _ in (200, MockHTTP.sse("Verbunden.")) }
        view.runConnectionTest()
        try await settle(700)
        _ = view.testResult
        view.abandonConnectionTest()
        MockHTTP.install { _ in
            (200, Data("data: {\"choices\":[{\"delta\":{\"content\":\"\"}}]}\ndata: [DONE]\n".utf8))
        }
        await view.testConnection()
        _ = view.testResult
        MockHTTP.install { _ in (500, Data("kaputt".utf8)) }
        await view.testConnection()
        _ = view.testResult
        await view.refreshBalance(provider: provider, key: "k")
        let saved = AppSettings.shared.connections
        AppSettings.shared.connections.openAICompatible.baseURL = "nicht wirklich eine adresse"
        AppSettings.shared.provider = .openAICompatible
        await view.testConnection()
        AppSettings.shared.connections = saved
        AppSettings.shared.provider = provider
    }

    func testSmokeTheSettingsSectionsAndSheetsDraw() async throws {
        let (store, cleaner) = stagedStoreWithCleaner("settings-sections")
        let view = SettingsView()
        await store.memory.add(text: "mag Tee", category: .likes, source: .explicit)
        let controller = mountView(view.environmentObject(store).environmentObject(cleaner),
                                   size: CGSize(width: 390, height: 1500))
        try await settleHosted(controller, milliseconds: 500)
        try await settle(300)
        view.showMemory = true
        view.showPriceWatch = true
        let second = mountView(view.environmentObject(store).environmentObject(cleaner),
                               size: CGSize(width: 390, height: 1500))
        try await settleHosted(second, milliseconds: 500)
        view.showMemory = false
        view.showPriceWatch = false
        try await settle(300)
        dismissPresentedSheets()
    }

    func testTheSettingsProfileSetters() {
        let settings = AppSettings.shared
        let provider = settings.provider
        let savedProfile = settings.profile
        settings.updateProfile(of: provider) { profile in
            profile.chatModel = "gap-chat"
            profile.visionModel = "gap-vision"
            profile.imageModel = "gap-image"
        }
        XCTAssertEqual(settings.profile(of: provider).chatModel, "gap-chat")
        settings.chatModel = "gap-chat-2"
        XCTAssertEqual(settings.chatModel, "gap-chat-2")
        settings.visionModel = "gap-vision-2"
        XCTAssertEqual(settings.visionModel, "gap-vision-2")
        settings.imageModel = "gap-image-2"
        XCTAssertEqual(settings.imageModel, "gap-image-2")
        settings.videoModel = "gap-video"
        XCTAssertEqual(settings.videoModel, "gap-video")
        settings.videoGenerationModel = "gap-video-gen"
        XCTAssertEqual(settings.videoGenerationModel, "gap-video-gen")
        _ = settings.videoCandidates
        _ = settings.videoGenerationCandidates
        XCTAssertTrue(settings.hasVideoModel)
        XCTAssertTrue(settings.hasVideoGenerationModel)
        XCTAssertEqual(settings.answeringModel(hasPictures: false, hasVideo: true), "gap-video")
        settings.forgetDeletedModel("gap-video", of: provider)
        XCTAssertFalse(settings.hasVideoModel)
        settings.chatThinkingLevel = .low
        XCTAssertEqual(settings.chatThinkingLevel, .low)
        _ = settings.profile.modelCaps
        _ = settings.modelsNeedingCaps
        _ = settings.answeringModel(hasPictures: true)
        _ = settings.connections
        settings.adopt(ModelListingResult(models: ["gap-a", "gap-b"], imageModels: ["gap-img"]), for: provider)
        XCTAssertTrue(settings.profile(of: provider).availableModels.contains("gap-a"))
        settings.profiles[provider] = savedProfile
    }

    func testSmokeTheModelCapsDiscovery() async {
        let settings = AppSettings.shared
        let provider = settings.provider
        let savedKey = settings.key(for: provider)
        settings.setKey("gap-caps-key", for: provider)
        defer { settings.setKey(savedKey, for: provider) }
        settings.updateProfile(of: provider) { profile in
            profile.availableModels = ["gap-model-1", "gap-model-2"]
            profile.modelCaps = [:]
        }
        await settings.refreshModelCaps(for: ["gap-model-1"], of: provider,
                                        using: GapDiscoverer(found: [:]))
        let discoverer = GapDiscoverer(found: ["gap-model-1": ModelCapabilities()])
        await settings.refreshModelCaps(for: ["gap-model-1"], of: provider, using: discoverer)
        await settings.refreshModelCaps(for: ["gap-model-1"], of: provider, using: discoverer)
        settings.updateProfile(of: provider) { profile in
            profile.availableModels = []
            profile.modelCaps = [:]
        }
    }

    func testTheModelReloadPaths() async throws {
        let settings = AppSettings.shared
        let provider = settings.provider
        let savedProfile = settings.profile
        settings.setKey("gap-reload-key", for: provider)
        MockHTTP.install { _ in
            (200, Data(#"{"data":[{"id":"gap-listed"}]}"#.utf8))
        }
        try? await settings.reloadModels(of: provider)
        MockHTTP.install { _ in (500, Data("kaputt".utf8)) }
        do {
            try await settings.reloadModels(of: provider)
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        settings.profiles[provider] = savedProfile
    }

    func testSmokeTheModelsViewDrawsAndLists() async throws {
        let settings = AppSettings.shared
        let provider = settings.provider
        let savedProfile = settings.profile
        settings.updateProfile(of: provider) { profile in
            profile.listingVersion = 0
        }
        settings.setKey("gap-models-key", for: provider)
        MockHTTP.install { _ in
            (200, Data(#"{"data":[{"id":"gap-listed-model"}]}"#.utf8))
        }
        var result: String?
        let binding = Binding(get: { result }, set: { result = $0 })
        let view = ModelsSettingsView(testResult: binding)
        let controller = mountView(Form { view }, size: CGSize(width: 390, height: 900))
        try await settleHosted(controller, milliseconds: 700)
        view.testResult = nil
        for action in MirrorTap.actions(in: view) { action() }
        try await settle(400)
        settings.profiles[provider] = savedProfile
    }
}

@MainActor
extension SettingsViewGapTests {
    func testSmokeTheBalanceRefreshAndBlockedKeys() async throws {
        let view = SettingsView()
        let provider = AppSettings.shared.provider
        AppSettings.shared.provider = .openRouter
        MockHTTP.install { _ in
            (200, Data(#"{"data":{"total_credits":10,"total_usage":2.5}}"#.utf8))
        }
        await view.refreshBalance(provider: .openRouter, key: "k")
        AppSettings.shared.reloadBlockedKeys()
        AppSettings.shared.provider = provider
    }

    func testSmokeTheConnectionProviderRowToggle() async throws {
        let (store, cleaner) = stagedStoreWithCleaner("settings-provider-row")
        let view = SettingsView()
        let controller = mountView(Form { view.providerSection }
            .environmentObject(store).environmentObject(cleaner),
                                   size: CGSize(width: 390, height: 900))
        try await settleHosted(controller, milliseconds: 500)
        for action in MirrorTap.actions(in: view.providerSection) { action() }
        dismissPresentedSheets()
    }
}

@MainActor
extension SettingsViewGapTests {
    func testSmokeTheModelsViewRendersUnavailableAndEmptyStates() async throws {
        let settings = AppSettings.shared
        let provider = settings.provider
        let savedProfile = settings.profile
        var result: String?
        let binding = Binding(get: { result }, set: { result = $0 })
        settings.provider = .deepSeek
        let unavailable = mountView(Form { ModelsSettingsView(testResult: binding) },
                                    size: CGSize(width: 390, height: 900))
        try await settleHosted(unavailable, milliseconds: 500)
        settings.provider = provider
        settings.updateProfile(of: provider) { profile in
            profile.availableModels = []
            profile.imageModels = []
            profile.chatModel = ""
            profile.visionModel = ""
            profile.imageModel = ""
        }
        let empty = mountView(Form { ModelsSettingsView(testResult: binding) },
                              size: CGSize(width: 390, height: 900))
        try await settleHosted(empty, milliseconds: 500)
        settings.setKey("gap-models-fail", for: provider)
        MockHTTP.install { _ in (500, Data("kaputt".utf8)) }
        settings.updateProfile(of: provider) { profile in
            profile.listingVersion = 0
        }
        let failing = mountView(Form { ModelsSettingsView(testResult: binding) },
                                size: CGSize(width: 390, height: 900))
        try await settleHosted(failing, milliseconds: 800)
        MockHTTP.uninstall()
        let busy = mountView(Form {
            SettingsBusyButton(title: "Laden", busyTitle: "Lädt", busy: true, symbol: "arrow.clockwise",
                               enabled: true, action: {})
        }, size: CGSize(width: 390, height: 200))
        try await settleHosted(busy, milliseconds: 200)
        settings.profiles[provider] = savedProfile
    }
}
