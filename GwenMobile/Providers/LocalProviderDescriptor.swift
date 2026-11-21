import GwenMobileKit
import Foundation

struct LocalModelLister: ModelListing {
    func list(baseURL: String, key: String) async throws -> ModelListingResult {
        let state = await LocalEngine.shared.modelSnapshot()
        let models = await Offload.value {
            LocalModelFiles().installedChoices()
                .filter { $0.id == state.loaded || $0.id == state.loading || LocalMemory.canHost($0.bytes) }
                .map(\.id)
        }
        return ModelListingResult(models: models, imageModels: [])
    }
}

struct LocalCapabilityDiscoverer: ModelDiscovering {
    static let thinking = ThinkingCapabilities(levels: [.low, .medium, .high],
                                               canSwitchOff: true,
                                               encoding: .openAI,
                                               probed: true)

    func discover(baseURL: String, key: String, models: [String]) async -> [String: ModelCapabilities] {
        await Offload.value {
            var found: [String: ModelCapabilities] = [:]
            for model in models {
                guard let choice = LocalCatalog.choice(for: model) else { continue }
                found[model] = ModelCapabilities(thinking: Self.thinking,
                                                 vision: choice.vision ? .supported : .rejected)
            }
            return found
        }
    }
}

struct LocalProviderDescriptor: ProviderDescriptor {
    let id = ProviderID.local
    let glyph = ProviderGlyph(text: "ON", red: 0.05, green: 0.62, blue: 0.36)
    let capabilities = ProviderCapabilities(chat: .available, vision: .probed, image: .unavailable)
    let defaultProfile = ProviderProfile()
    let thinkingEncoding = ThinkingEncoding.openAI
    let modelLister: any ModelListing = LocalModelLister()
    let modelDiscoverer: any ModelDiscovering = LocalCapabilityDiscoverer()
    let keychainAccount = "local_device_no_key"

    var title: String { L.t("provider_local_title") }
    var subtitle: String { L.t("provider_local_subtitle") }
    var footer: String { L.t("local_footer") }
    var modelsFooter: String { L.t("local_models_footer") }

    func baseURL(_ connections: ProviderConnections) -> String {
        LocalEndpoint.baseURL
    }

    func isConfigured(_ connections: ProviderConnections, key: String) -> Bool {
        true
    }

    func keyIsOptional(_ connections: ProviderConnections) -> Bool {
        true
    }

    func keyPlaceholder(_ connections: ProviderConnections) -> String {
        L.t("key_optional_local")
    }

    func usesPresetURL(_ connections: ProviderConnections) -> Bool {
        true
    }
}
