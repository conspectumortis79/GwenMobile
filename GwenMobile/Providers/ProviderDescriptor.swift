import GwenMobileKit
import Foundation

enum ProviderID: String, CaseIterable, Identifiable, Codable, CodingKeyRepresentable, Sendable {
    case qwenCloud = "qwen"
    case openAICompatible = "openai"
    case local = "local"
    case openRouter = "openrouter"
    case deepSeek = "deepseek"

    var id: String { rawValue }

    var descriptor: any ProviderDescriptor {
        switch self {
        case .qwenCloud: return QwenCloudDescriptor()
        case .openAICompatible: return OpenAICompatibleDescriptor()
        case .local: return LocalProviderDescriptor()
        case .openRouter: return OpenRouterDescriptor()
        case .deepSeek: return DeepSeekDescriptor()
        }
    }
}

enum ProviderCatalog {
    static var all: [any ProviderDescriptor] { ProviderID.allCases.map(\.descriptor) }
}

enum FeatureAvailability: String, Sendable, Equatable {
    case available
    case probed
    case unavailable

    var labelKey: String {
        switch self {
        case .available: return "availability_available"
        case .probed: return "availability_probed"
        case .unavailable: return "availability_unavailable"
        }
    }
}

enum ProviderFeature: String, CaseIterable, Identifiable, Sendable {
    case chat
    case vision
    case image
    case video
    case videoGeneration = "video_generation"

    var id: String { rawValue }
    var labelKey: String { "feature_\(rawValue)" }
}

struct ProviderCapabilities: Sendable, Equatable {
    var chat: FeatureAvailability
    var vision: FeatureAvailability
    var image: FeatureAvailability
    var video: FeatureAvailability = .unavailable
    var videoGeneration: FeatureAvailability = .unavailable

    subscript(feature: ProviderFeature) -> FeatureAvailability {
        switch feature {
        case .chat: return chat
        case .vision: return vision
        case .image: return image
        case .video: return video
        case .videoGeneration: return videoGeneration
        }
    }
}

struct ProviderGlyph: Sendable, Equatable {
    let text: String
    let red: Double
    let green: Double
    let blue: Double
}

struct ProviderConnections: Codable, Equatable, Sendable {
    var qwenCloud = QwenCloudConfig()
    var openAICompatible = OpenAICompatibleConfig()
    var openRouter = OpenRouterConfig()
}

protocol ProviderDescriptor: Sendable {
    var id: ProviderID { get }
    var glyph: ProviderGlyph { get }
    var capabilities: ProviderCapabilities { get }
    var thinkingEncoding: ThinkingEncoding { get }
    var modelDiscoverer: any ModelDiscovering { get }
    var modelLister: any ModelListing { get }
    var imageBackend: (any ImageGenerating)? { get }
    var videoGenerationBackend: (any VideoGenerating)? { get }
    var defaultProfile: ProviderProfile { get }
    var keychainAccount: String { get }
    var consoleLink: URL? { get }
    var consoleLinkTitle: String { get }
    var title: String { get }
    var subtitle: String { get }
    var footer: String { get }
    var modelsFooter: String { get }
    func baseURL(_ connections: ProviderConnections) -> String
    func isConfigured(_ connections: ProviderConnections, key: String) -> Bool
    func keyIsOptional(_ connections: ProviderConnections) -> Bool
    func keyPlaceholder(_ connections: ProviderConnections) -> String
    func usesPresetURL(_ connections: ProviderConnections) -> Bool
    func requestDecorator(_ connections: ProviderConnections) -> any RequestDecorating
}

extension ProviderDescriptor {
    var consoleLink: URL? { nil }
    var modelLister: any ModelListing { OpenAIModelLister() }
    var imageBackend: (any ImageGenerating)? { nil }
    var videoGenerationBackend: (any VideoGenerating)? { nil }
    var consoleLinkTitle: String { "" }
    func keyIsOptional(_ connections: ProviderConnections) -> Bool { false }
    func keyPlaceholder(_ connections: ProviderConnections) -> String { "sk-…" }
    func usesPresetURL(_ connections: ProviderConnections) -> Bool { true }
    func requestDecorator(_ connections: ProviderConnections) -> any RequestDecorating { NoRequestDecoration() }
}

protocol AccountBalanceReporting: Sendable {
    func accountBalance(key: String) async -> String?
}
