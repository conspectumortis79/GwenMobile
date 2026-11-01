import GwenMobileKit
import Foundation

struct ProviderProfile: Codable, Equatable, Sendable {
    static let currentListingVersion = 2

    var chatModel = ""
    var visionModel = ""
    var imageModel = ""
    var videoModel = ""
    var videoGenerationModel = ""
    var chatThinkingLevel: ThinkingLevel = .modelDefault
    var availableModels: [String] = []
    var imageModels: [String] = []
    var videoGenerationModels: [String] = []
    var modelCaps: [String: ModelCapabilities] = [:]
    var listingVersion = 0

    init(chatModel: String = "", visionModel: String = "", imageModel: String = "",
         videoModel: String = "", videoGenerationModel: String = "",
         chatThinkingLevel: ThinkingLevel = .modelDefault, availableModels: [String] = [],
         imageModels: [String] = [], videoGenerationModels: [String] = [],
         modelCaps: [String: ModelCapabilities] = [:], listingVersion: Int = 0) {
        self.chatModel = chatModel
        self.visionModel = visionModel
        self.imageModel = imageModel
        self.videoModel = videoModel
        self.videoGenerationModel = videoGenerationModel
        self.chatThinkingLevel = chatThinkingLevel
        self.availableModels = availableModels
        self.imageModels = imageModels
        self.videoGenerationModels = videoGenerationModels
        self.modelCaps = modelCaps
        self.listingVersion = listingVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        chatModel = try container.decodeIfPresent(String.self, forKey: .chatModel) ?? ""
        visionModel = try container.decodeIfPresent(String.self, forKey: .visionModel) ?? ""
        imageModel = try container.decodeIfPresent(String.self, forKey: .imageModel) ?? ""
        videoModel = try container.decodeIfPresent(String.self, forKey: .videoModel) ?? ""
        videoGenerationModel = try container.decodeIfPresent(String.self, forKey: .videoGenerationModel) ?? ""
        chatThinkingLevel = try container.decodeIfPresent(ThinkingLevel.self, forKey: .chatThinkingLevel) ?? .modelDefault
        availableModels = try container.decodeIfPresent([String].self, forKey: .availableModels) ?? []
        imageModels = try container.decodeIfPresent([String].self, forKey: .imageModels)
            ?? ModelFilter.imageCandidates(availableModels)
        videoGenerationModels = try container.decodeIfPresent([String].self, forKey: .videoGenerationModels) ?? []
        modelCaps = try container.decodeIfPresent([String: ModelCapabilities].self, forKey: .modelCaps) ?? [:]
        listingVersion = try container.decodeIfPresent(Int.self, forKey: .listingVersion) ?? 0
    }

    var needsListing: Bool { availableModels.isEmpty || listingVersion < Self.currentListingVersion }

    func capabilities(for model: String) -> ModelCapabilities {
        modelCaps[model] ?? ModelCapabilities()
    }

    var textCandidates: [String] { ModelFilter.textCandidates(availableModels) }
    var imageCandidates: [String] { imageModels }
    var visionCandidates: [String] { ModelFilter.visionCandidates(availableModels, caps: modelCaps) }
    var videoCandidates: [String] { ModelFilter.videoCandidates(availableModels, caps: modelCaps) }

    var hasVisionCaps: Bool {
        textCandidates.contains { modelCaps[$0]?.vision.isKnown == true }
    }

    var hasVideoCaps: Bool {
        textCandidates.contains { modelCaps[$0]?.video.isKnown == true }
    }

    func answeringModel(hasPictures: Bool, hasVideo: Bool = false) -> String {
        if hasVideo, !videoModel.isEmpty { return videoModel }
        return hasPictures && !visionModel.isEmpty ? visionModel : chatModel
    }

    func needsDiscovery(_ model: String, encoding: ThinkingEncoding) -> Bool {
        modelCaps[model]?.isCurrent(for: encoding) != true
    }

    func modelsNeedingCaps(encoding: ThinkingEncoding) -> [String] {
        textCandidates.filter { needsDiscovery($0, encoding: encoding) }
    }

    mutating func adopt(_ listing: ModelListingResult) {
        let previousVersion = listingVersion
        availableModels = listing.models
        imageModels = listing.imageModels
        if !listing.videoGenerationModels.isEmpty {
            videoGenerationModels = listing.videoGenerationModels
        }
        listingVersion = Self.currentListingVersion
        if previousVersion < Self.currentListingVersion { modelCaps.removeAll() }
        ensure(\.chatModel, valid: listing.models, fallback: textCandidates)
        ensure(\.imageModel, valid: imageModels, fallback: imageModels)
        ensure(\.videoGenerationModel, valid: videoGenerationModels, fallback: videoGenerationModels)
    }

    mutating func adoptVisionCandidates() {
        ensure(\.visionModel, valid: visionCandidates, fallback: visionCandidates)
    }

    mutating func adoptVideoCandidates() {
        ensure(\.videoModel, valid: videoCandidates, fallback: videoCandidates)
    }

    mutating func merge(caps found: [String: ModelCapabilities]) {
        modelCaps.merge(found) { _, new in new }
        if capabilities(for: visionModel).vision == .rejected, let first = visionCandidates.first {
            visionModel = first
        }
        if capabilities(for: videoModel).video == .rejected, let first = videoCandidates.first {
            videoModel = first
        }
    }

    private mutating func ensure(_ keyPath: WritableKeyPath<ProviderProfile, String>,
                                 valid: [String], fallback: [String]) {
        if !valid.contains(self[keyPath: keyPath]), let first = fallback.first {
            self[keyPath: keyPath] = first
        }
    }
}
