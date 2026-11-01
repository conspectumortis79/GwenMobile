@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class ProviderProfileTests: XCTestCase {
    private let models = ["qwen3.8-flash", "qwen3.8-max", "wan2.7-image", "qwen-audio-3.0-realtime-plus", "qwen-tts"]

    func testAdoptingModelsKeepsValidSelectionsAndReplacesStaleOnes() {
        var profile = ProviderProfile(chatModel: "qwen3.8-max", visionModel: "gone", imageModel: "gone")
        profile.adopt(ModelListingResult(models: models, imageModels: ModelFilter.imageCandidates(models)))
        XCTAssertEqual(profile.availableModels, models)
        XCTAssertEqual(profile.imageCandidates, ["wan2.7-image"])
        XCTAssertEqual(profile.chatModel, "qwen3.8-max")
        XCTAssertEqual(profile.imageModel, "wan2.7-image")
        XCTAssertEqual(profile.visionModel, "gone")
    }

    func testAdoptingAnEmptyListLeavesSelectionsUntouched() {
        var profile = QwenCloudDescriptor().defaultProfile
        profile.adopt(ModelListingResult(models: [], imageModels: []))
        var expected = QwenCloudDescriptor().defaultProfile
        expected.listingVersion = ProviderProfile.currentListingVersion
        XCTAssertEqual(profile, expected)
    }

    func testVisionCandidatesFollowTheProbesAndRejectedModelsAreReplaced() {
        var profile = ProviderProfile(visionModel: "qwen3.8-flash", availableModels: models)
        XCTAssertFalse(profile.hasVisionCaps)
        XCTAssertEqual(profile.modelsNeedingCaps(encoding: .dashScope), ["qwen3.8-flash", "qwen3.8-max"])
        profile.merge(caps: [
            "qwen3.8-flash": ModelCapabilities(thinking: .unknown, vision: .rejected),
            "qwen3.8-max": ModelCapabilities(thinking: .unknown, vision: .supported),
        ])
        XCTAssertTrue(profile.hasVisionCaps)
        XCTAssertEqual(profile.visionCandidates, ["qwen3.8-max"])
        XCTAssertEqual(profile.visionModel, "qwen3.8-max")
        profile.visionModel = "qwen3.8-flash"
        profile.adoptVisionCandidates()
        XCTAssertEqual(profile.visionModel, "qwen3.8-max")
    }

    func testVideoCandidatesFollowTheVideoCapsAndTheGenerationList() {
        var profile = ProviderProfile(videoModel: "a", videoGenerationModel: "wan",
                                      availableModels: ["a", "b", "c"],
                                      videoGenerationModels: ["wan", "other"])
        profile.merge(caps: ["a": ModelCapabilities(video: .supported),
                             "b": ModelCapabilities(video: .rejected)])
        XCTAssertEqual(profile.videoCandidates, ["a"])
        XCTAssertEqual(profile.answeringModel(hasPictures: false, hasVideo: true), "a")
        profile.videoModel = "b"
        profile.adoptVideoCandidates()
        XCTAssertEqual(profile.videoModel, "a")
        XCTAssertEqual(profile.videoGenerationModel, "wan")
    }

    func testTheAnsweringModelFollowsThePicturesOfTheTurn() {
        let profile = ProviderProfile(chatModel: "qwen3.8-flash", visionModel: "qwen3.8-max",
                                      availableModels: models,
                                      modelCaps: ["qwen3.8-flash": ModelCapabilities(thinking: .unknown,
                                                                                     vision: .rejected),
                                                  "qwen3.8-max": ModelCapabilities(thinking: .unknown,
                                                                                   vision: .supported)])
        XCTAssertEqual(profile.answeringModel(hasPictures: false), "qwen3.8-flash")
        XCTAssertEqual(profile.answeringModel(hasPictures: true), "qwen3.8-max")
    }

    func testAdoptingAVideoGenerationListKeepsOrReplacesTheModel() {
        var fresh = ProviderProfile(videoGenerationModel: "gone")
        fresh.adopt(ModelListingResult(models: ["chat"], imageModels: [],
                                       videoGenerationModels: ["wan", "other"]))
        XCTAssertEqual(fresh.videoGenerationModels, ["wan", "other"])
        XCTAssertEqual(fresh.videoGenerationModel, "wan")
        var kept = ProviderProfile(videoGenerationModel: "wan",
                                   videoGenerationModels: ["wan"])
        kept.adopt(ModelListingResult(models: ["chat"], imageModels: []))
        XCTAssertEqual(kept.videoGenerationModel, "wan")
        XCTAssertEqual(kept.videoGenerationModels, ["wan"])
    }

    func testAVideoModelThatCannotSeeIsReplacedByTheFirstVideoCandidate() {
        var profile = ProviderProfile(videoModel: "blind", availableModels: ["blind", "sees"])
        profile.merge(caps: ["blind": ModelCapabilities(video: .rejected),
                             "sees": ModelCapabilities(video: .supported)])
        XCTAssertTrue(profile.hasVideoCaps)
        XCTAssertEqual(profile.videoCandidates, ["sees"])
        XCTAssertEqual(profile.videoModel, "sees")
    }

    func testAnUnsetVisionModelNeverLeavesTheTurnWithoutAModel() {
        let profile = ProviderProfile(chatModel: "llama3.2-vision")
        XCTAssertTrue(profile.visionModel.isEmpty)
        XCTAssertEqual(profile.answeringModel(hasPictures: true), "llama3.2-vision")
        XCTAssertEqual(profile.answeringModel(hasPictures: false), "llama3.2-vision")
    }

    func testALegacyRouterModelIsIgnored() throws {
        let legacy = Data(#"{"chatModel":"chat-model","routerModel":"router-model"}"#.utf8)
        let profile = try JSONDecoder().decode(ProviderProfile.self, from: legacy)
        XCTAssertEqual(profile.chatModel, "chat-model")
        XCTAssertEqual(profile.answeringModel(hasPictures: false), "chat-model")
        XCTAssertEqual(profile.answeringModel(hasPictures: true), "chat-model")
    }

    func testCapabilitySubscriptMirrorsTheFields() {
        let caps = ProviderCapabilities(chat: .available, vision: .probed, image: .unavailable)
        XCTAssertEqual(caps[.chat], .available)
        XCTAssertEqual(caps[.vision], .probed)
        XCTAssertEqual(caps[.image], .unavailable)
        XCTAssertEqual(caps[.video], .unavailable)
        XCTAssertEqual(caps[.videoGeneration], .unavailable)
        XCTAssertEqual(FeatureAvailability.unavailable.labelKey, "availability_unavailable")
        XCTAssertEqual(ProviderFeature.image.labelKey, "feature_image")
    }

    func testProfilesAndConnectionsSurviveTheJSONRoundTrip() throws {
        var connections = ProviderConnections()
        connections.qwenCloud = QwenCloudConfig(billing: .payAsYouGo, region: .eu, workspace: "llm-1")
        connections.openAICompatible.select(presetID: "groq")
        connections.openRouter.appName = "App"
        let profiles: [ProviderID: ProviderProfile] = [
            .qwenCloud: QwenCloudDescriptor().defaultProfile,
            .openRouter: ProviderProfile(chatModel: "openai/gpt-4o-mini", chatThinkingLevel: .high),
        ]
        let decodedConnections = try JSONDecoder().decode(ProviderConnections.self,
                                                          from: JSONEncoder().encode(connections))
        let decodedProfiles = try JSONDecoder().decode([ProviderID: ProviderProfile].self,
                                                       from: JSONEncoder().encode(profiles))
        XCTAssertEqual(decodedConnections, connections)
        XCTAssertEqual(decodedProfiles, profiles)
    }

    func testCatalogListsEveryProviderOnceInMenuOrder() {
        XCTAssertEqual(ProviderCatalog.all.map(\.id), [.qwenCloud, .openAICompatible, .local, .openRouter, .deepSeek])
        XCTAssertEqual(Set(ProviderCatalog.all.map(\.keychainAccount)).count, 5)
        for descriptor in ProviderCatalog.all {
            XCTAssertFalse(descriptor.title.isEmpty)
            XCTAssertFalse(descriptor.subtitle.isEmpty)
            XCTAssertFalse(descriptor.footer.isEmpty)
            XCTAssertFalse(descriptor.modelsFooter.isEmpty)
            XCTAssertFalse(descriptor.glyph.text.isEmpty)
        }
    }
}
