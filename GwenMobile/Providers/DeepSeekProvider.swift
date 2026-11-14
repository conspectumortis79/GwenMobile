import GwenMobileKit
import Foundation

struct DeepSeekBalance: Decodable, Equatable, Sendable {
    struct Info: Decodable, Equatable, Sendable {
        var currency: String
        var totalBalance: String
        var grantedBalance: String? = nil
        var toppedUpBalance: String? = nil

        enum CodingKeys: String, CodingKey {
            case currency
            case totalBalance = "total_balance"
            case grantedBalance = "granted_balance"
            case toppedUpBalance = "topped_up_balance"
        }
    }

    var isAvailable: Bool
    var balanceInfos: [Info]

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }

    var providerBalance: ProviderBalance {
        let entries = balanceInfos.map {
            ProviderBalance.Entry(total: $0.totalBalance, currency: $0.currency,
                                  granted: $0.grantedBalance, toppedUp: $0.toppedUpBalance)
        }
        return ProviderBalance(status: isAvailable && !entries.isEmpty ? .available : .unavailable,
                               entries: entries)
    }
}

enum DeepSeekAPI {
    static let baseURL = "https://api.deepseek.com"
    static let balancePath = "/user/balance"

    static func balanceRequest(key: String) throws -> URLRequest {
        try HTTP.authorizedGET(baseURL: baseURL, path: balancePath, key: key,
                               timeout: APITimeout.modelsRequest)
    }

    static func fetchBalance(key: String) async throws -> DeepSeekBalance {
        try await ProviderPayload.fetch(request: balanceRequest(key: key))
    }
}

struct DeepSeekDescriptor: ProviderDescriptor, AccountBalanceReporting {
    static let usageLink = URL(string: "https://platform.deepseek.com/usage")

    let id = ProviderID.deepSeek
    let glyph = ProviderGlyph(text: "DS", red: 0.30, green: 0.42, blue: 1.0)
    let capabilities = ProviderCapabilities(chat: .available, vision: .probed, image: .unavailable)
    let defaultProfile = ProviderProfile()
    let thinkingEncoding = ThinkingEncoding.openAI
    var modelDiscoverer: any ModelDiscovering { DeepSeekModelCatalog() }
    let keychainAccount = "deepseek_api_key"
    let consoleLink: URL? = URL(string: "https://platform.deepseek.com/api_keys")

    var consoleLinkTitle: String { L.t("deepseek_create_key") }
    var title: String { L.t("provider_deepseek_title") }
    var subtitle: String { L.t("provider_deepseek_subtitle") }
    var footer: String { L.t("deepseek_footer") }
    var modelsFooter: String { L.t("models_footer_deepseek") }

    func baseURL(_ connections: ProviderConnections) -> String {
        DeepSeekAPI.baseURL
    }

    func isConfigured(_ connections: ProviderConnections, key: String) -> Bool {
        !key.isEmpty
    }

    func accountBalance(key: String) async throws -> ProviderBalance {
        try await DeepSeekAPI.fetchBalance(key: key).providerBalance
    }
}
