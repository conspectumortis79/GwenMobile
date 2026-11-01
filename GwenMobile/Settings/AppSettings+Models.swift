import GwenMobileKit
import Foundation

extension AppSettings {
    var descriptor: any ProviderDescriptor { provider.descriptor }
    var capabilities: ProviderCapabilities { descriptor.capabilities }
    var hasImageModel: Bool { descriptor.imageBackend != nil && !imageModel.isEmpty }
    var hasVideoGenerationModel: Bool {
        descriptor.videoGenerationBackend != nil && !videoGenerationModel.isEmpty
    }
    var connectionIdentity: ConnectionIdentity { ConnectionIdentity(provider: provider, baseURL: baseURL) }

    var baseURL: String { baseURL(for: provider) }
    var isConfigured: Bool { isConfigured(for: provider) }

    func profile(of provider: ProviderID) -> ProviderProfile {
        profiles[provider] ?? provider.descriptor.defaultProfile
    }

    func updateProfile(of provider: ProviderID, _ body: (inout ProviderProfile) -> Void) {
        var changed = profile(of: provider)
        body(&changed)
        profiles[provider] = changed
    }

    func forgetDeletedModel(_ model: String, of provider: ProviderID? = nil) {
        updateProfile(of: provider ?? self.provider) { profile in
            if profile.chatModel == model { profile.chatModel = "" }
            if profile.visionModel == model { profile.visionModel = "" }
            if profile.imageModel == model { profile.imageModel = "" }
            if profile.videoModel == model { profile.videoModel = "" }
            if profile.videoGenerationModel == model { profile.videoGenerationModel = "" }
            profile.availableModels.removeAll { $0 == model }
            profile.imageModels.removeAll { $0 == model }
            profile.videoGenerationModels.removeAll { $0 == model }
            profile.modelCaps[model] = nil
        }
    }

    var profile: ProviderProfile {
        get { profile(of: provider) }
        set { profiles[provider] = newValue }
    }

    var chatModel: String {
        get { profile.chatModel }
        set { profile.chatModel = newValue }
    }
    var visionModel: String {
        get { profile.visionModel }
        set { profile.visionModel = newValue }
    }
    var imageModel: String {
        get { profile.imageModel }
        set { profile.imageModel = newValue }
    }
    var videoModel: String {
        get { profile.videoModel }
        set { profile.videoModel = newValue }
    }
    var videoGenerationModel: String {
        get { profile.videoGenerationModel }
        set { profile.videoGenerationModel = newValue }
    }
    var chatThinkingLevel: ThinkingLevel {
        get { profile.chatThinkingLevel }
        set { profile.chatThinkingLevel = newValue }
    }
    var availableModels: [String] { profile.availableModels }
    var visionCandidates: [String] { profile.visionCandidates }
    var videoCandidates: [String] { profile.videoCandidates }
    var videoGenerationCandidates: [String] { profile.videoGenerationModels }
    var hasVisionModel: Bool { !visionModel.trimmed.isEmpty }
    var hasVideoModel: Bool { !videoModel.trimmed.isEmpty }
    var hasVisionCaps: Bool { profile.hasVisionCaps }
    var hasVideoCaps: Bool { profile.hasVideoCaps }
    var modelsNeedingCaps: [String] { profile.modelsNeedingCaps(encoding: descriptor.thinkingEncoding) }

    func answeringModel(hasPictures: Bool, hasVideo: Bool = false) -> String {
        profile.answeringModel(hasPictures: hasPictures, hasVideo: hasVideo)
    }

    func capabilities(for model: String) -> ModelCapabilities {
        profile.capabilities(for: model)
    }

    func thinkingDirective(for model: String) -> ThinkingDirective {
        capabilities(for: model).thinking.directive(for: chatThinkingLevel)
    }

    func thinkingOffDirective(for model: String) -> ThinkingDirective {
        capabilities(for: model).thinking.directive(for: .off)
    }

    func activeThinkingLevel(for model: String) -> ThinkingLevel? {
        thinkingDirective(for: model).sendsAnything ? chatThinkingLevel : nil
    }

    func adopt(_ listing: ModelListingResult, for provider: ProviderID) {
        updateProfile(of: provider) { $0.adopt(listing) }
    }

    func reloadModels(of provider: ProviderID? = nil) async throws {
        let target = provider ?? self.provider
        let listing = try await target.descriptor.modelLister.list(baseURL: baseURL(for: target), key: key(for: target))
        adopt(listing, for: target)
        await refreshModelCaps(for: ModelFilter.textCandidates(listing.models), of: target)
        updateProfile(of: target) { $0.adoptVisionCandidates() }
        updateProfile(of: target) { $0.adoptVideoCandidates() }
    }

    func refreshModelCaps(for models: [String], of provider: ProviderID? = nil,
                          using discoverer: (any ModelDiscovering)? = nil) async {
        let target = provider ?? self.provider
        let descriptor = target.descriptor
        let current = profile(of: target)
        let pending = models.filter { current.needsDiscovery($0, encoding: descriptor.thinkingEncoding) }
        guard isConfigured(for: target), !pending.isEmpty, !probing.contains(target) else { return }
        probing.insert(target)
        defer { probing.remove(target) }
        let found = await (discoverer ?? descriptor.modelDiscoverer)
            .discover(baseURL: baseURL(for: target), key: key(for: target), models: pending)
        guard !found.isEmpty else { return }
        updateProfile(of: target) { $0.merge(caps: found) }
    }
}
