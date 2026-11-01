import GwenMobileKit
import Foundation

struct OpenAIPreset: Identifiable, Hashable, Sendable {
    let id: String
    let labelKey: String?
    let name: String
    let url: String
    let local: Bool

    init(id: String, name: String, url: String, local: Bool = false, labelKey: String? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.local = local
        self.labelKey = labelKey
    }

    nonisolated var label: String { labelKey.map { L.t($0) } ?? name }
}

enum OpenAIPresets {
    static let custom = OpenAIPreset(id: "custom", name: "", url: "", labelKey: "preset_custom")

    static let all: [OpenAIPreset] = [
        custom,
        OpenAIPreset(id: "openai", name: "OpenAI", url: "https://api.openai.com/v1"),
        OpenAIPreset(id: "groq", name: "Groq", url: "https://api.groq.com/openai/v1"),
        OpenAIPreset(id: "mistral", name: "Mistral", url: "https://api.mistral.ai/v1"),
        OpenAIPreset(id: "together", name: "Together AI", url: "https://api.together.xyz/v1"),
        OpenAIPreset(id: "ollama", name: "Ollama", url: "http://localhost:11434/v1", local: true, labelKey: "preset_ollama"),
        OpenAIPreset(id: "lmstudio", name: "LM Studio", url: "http://localhost:1234/v1", local: true, labelKey: "preset_lmstudio"),
    ]

    static func preset(id: String) -> OpenAIPreset {
        all.first { $0.id == id } ?? custom
    }

    static func matching(url: String) -> OpenAIPreset? {
        let trimmed = HTTP.root(url)
        guard !trimmed.isEmpty else { return nil }
        return all.first { !$0.url.isEmpty && HTTP.root($0.url) == trimmed }
    }
}

struct OpenAICompatibleConfig: Codable, Equatable, Sendable {
    var preset = "openai"
    var baseURL = "https://api.openai.com/v1"

    init(preset: String = "openai", baseURL: String = "https://api.openai.com/v1") {
        self.preset = preset
        self.baseURL = baseURL
    }

    init(customURL: String) {
        baseURL = customURL
        preset = OpenAIPresets.matching(url: customURL)?.id ?? OpenAIPresets.custom.id
    }

    var selectedPreset: OpenAIPreset { OpenAIPresets.preset(id: preset) }
    var keyIsOptional: Bool { selectedPreset.local }

    mutating func select(presetID: String) {
        let chosen = OpenAIPresets.preset(id: presetID)
        preset = chosen.id
        baseURL = chosen.url
    }

    mutating func edit(baseURL new: String) {
        baseURL = new
        preset = OpenAIPresets.matching(url: new)?.id ?? OpenAIPresets.custom.id
    }
}

struct OpenAICompatibleModelLister: ModelListing {
    func list(baseURL: String, key: String) async throws -> ModelListingResult {
        let models = try await QwenAPI.fetchModels(baseURL: baseURL, key: key)
        let videoModels = (try? await OpenAIVideoAPI.fetchModelIDs(baseURL: baseURL, key: key)) ?? []
        return ModelListingResult(models: models,
                                  imageModels: ModelFilter.imageCandidates(models),
                                  videoGenerationModels: videoModels.isEmpty
                                      ? ModelFilter.videoGenerationCandidates(models)
                                      : videoModels)
    }
}

struct OpenAICompatibleDescriptor: ProviderDescriptor {
    let id = ProviderID.openAICompatible
    let glyph = ProviderGlyph(text: "AI", red: 0.06, green: 0.64, blue: 0.5)
    let capabilities = ProviderCapabilities(chat: .available, vision: .probed, image: .unavailable,
                                            videoGeneration: .probed)
    let defaultProfile = ProviderProfile()
    let thinkingEncoding = ThinkingEncoding.openAI
    var modelDiscoverer: any ModelDiscovering { CapabilityProber.openAI }
    var modelLister: any ModelListing { OpenAICompatibleModelLister() }
    var videoGenerationBackend: (any VideoGenerating)? { OpenAIVideoBackend() }
    let keychainAccount = "openai_compatible_api_key"

    var title: String { L.t("provider_openai_title") }
    var subtitle: String { L.t("provider_openai_subtitle") }
    var footer: String { L.t("openai_footer") }
    var modelsFooter: String { L.t("models_footer_openai") }

    func baseURL(_ connections: ProviderConnections) -> String {
        connections.openAICompatible.baseURL.trimmed
    }

    func isConfigured(_ connections: ProviderConnections, key: String) -> Bool {
        !baseURL(connections).isEmpty && (!key.isEmpty || keyIsOptional(connections))
    }

    func keyIsOptional(_ connections: ProviderConnections) -> Bool {
        connections.openAICompatible.keyIsOptional
    }

    func keyPlaceholder(_ connections: ProviderConnections) -> String {
        keyIsOptional(connections) ? L.t("key_optional_local") : "sk-…"
    }

    func usesPresetURL(_ connections: ProviderConnections) -> Bool {
        OpenAIPresets.matching(url: connections.openAICompatible.baseURL) != nil
    }
}
