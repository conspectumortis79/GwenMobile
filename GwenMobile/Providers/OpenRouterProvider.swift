import GwenMobileKit
import Foundation

struct OpenRouterConfig: Codable, Equatable, Sendable {
    var appName = ""

    var trimmedAppName: String { appName.trimmed }
}

struct OpenRouterAttribution: RequestDecorating, Equatable {
    static let referer = "https://github.com/pamo97/GwenMobile"
    static let hiddenVisibility = "hidden"

    let appName: String

    func decorate(_ request: inout URLRequest) {
        let name = appName.trimmed
        guard !name.isEmpty else { return }
        request.setValue(Self.referer, forHTTPHeaderField: "HTTP-Referer")
        request.setValue(name, forHTTPHeaderField: "X-OpenRouter-Title")
        request.setValue(name, forHTTPHeaderField: "X-Title")
        request.setValue(Self.hiddenVisibility, forHTTPHeaderField: "X-OpenRouter-App-Visibility")
    }
}

struct OpenRouterKeyInfo: Decodable, Equatable, Sendable {
    struct Payload: Decodable, Equatable, Sendable {
        var limitRemaining: Double?
        var usage: Double

        enum CodingKeys: String, CodingKey {
            case limitRemaining = "limit_remaining"
            case usage
        }
    }

    var data: Payload

    var balanceText: String {
        if let remaining = data.limitRemaining {
            return L.fmt("openrouter_remaining", OpenRouterAPI.dollars(remaining))
        }
        return L.fmt("openrouter_usage", OpenRouterAPI.dollars(data.usage))
    }
}

enum OpenRouterAPI {
    static let baseURL = "https://openrouter.ai/api/v1"
    static let keyPath = "/key"

    static func keyInfoRequest(key: String) throws -> URLRequest {
        try HTTP.authorizedGET(baseURL: baseURL, path: keyPath, key: key,
                               timeout: APITimeout.modelsRequest)
    }

    static func fetchKeyInfo(key: String) async throws -> OpenRouterKeyInfo {
        try await ProviderPayload.fetch(OpenRouterKeyInfo.self, request: keyInfoRequest(key: key))
    }

    static func dollars(_ amount: Double) -> String {
        let locale = L.lang.locale
        let formatter = formatters.mutate { stored -> NumberFormatter in
            if let found = stored[locale.identifier] { return found }
            let made = NumberFormatter()
            made.numberStyle = .decimal
            made.minimumFractionDigits = 2
            made.maximumFractionDigits = 2
            made.locale = locale
            stored[locale.identifier] = made
            return made
        }
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
    }

    private static let formatters = LockedValue([String: NumberFormatter]())
}

struct OpenRouterDescriptor: ProviderDescriptor, AccountBalanceReporting {
    let id = ProviderID.openRouter
    let glyph = ProviderGlyph(text: "OR", red: 0.12, green: 0.12, blue: 0.12)
    let capabilities = ProviderCapabilities(chat: .available, vision: .available, image: .available,
                                            video: .available, videoGeneration: .available)
    let defaultProfile = ProviderProfile()
    let thinkingEncoding = ThinkingEncoding.openRouter
    var modelDiscoverer: any ModelDiscovering { OpenRouterModelCatalog() }
    var modelLister: any ModelListing { OpenRouterModelLister() }
    var imageBackend: (any ImageGenerating)? { OpenRouterImageBackend() }
    var videoGenerationBackend: (any VideoGenerating)? { OpenRouterVideoBackend() }
    let keychainAccount = "openrouter_api_key"
    let consoleLink: URL? = URL(string: "https://openrouter.ai/settings/keys")

    var consoleLinkTitle: String { L.t("openrouter_create_key") }
    var title: String { L.t("provider_openrouter_title") }
    var subtitle: String { L.t("provider_openrouter_subtitle") }
    var footer: String { L.t("openrouter_footer") }
    var modelsFooter: String { L.t("models_footer_openrouter") }

    func baseURL(_ connections: ProviderConnections) -> String {
        OpenRouterAPI.baseURL
    }

    func isConfigured(_ connections: ProviderConnections, key: String) -> Bool {
        !key.isEmpty
    }

    func keyPlaceholder(_ connections: ProviderConnections) -> String { "sk-or-v1-…" }

    func requestDecorator(_ connections: ProviderConnections) -> any RequestDecorating {
        OpenRouterAttribution(appName: connections.openRouter.trimmedAppName)
    }

    func accountBalance(key: String) async -> String? {
        (try? await OpenRouterAPI.fetchKeyInfo(key: key))?.balanceText
    }
}
