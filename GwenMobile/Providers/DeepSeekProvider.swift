import GwenMobileKit
import Foundation

struct DeepSeekBalance: Decodable, Equatable, Sendable {
    struct Info: Decodable, Equatable, Sendable {
        var currency: String
        var totalBalance: String

        enum CodingKeys: String, CodingKey {
            case currency
            case totalBalance = "total_balance"
        }
    }

    var isAvailable: Bool
    var balanceInfos: [Info]

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }

    var text: String {
        guard isAvailable else { return L.t("deepseek_no_balance") }
        let parts = balanceInfos.map { L.fmt2("deepseek_balance", $0.totalBalance, $0.currency) }
        return parts.isEmpty ? L.t("deepseek_no_balance") : parts.joined(separator: " · ")
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
        try await ProviderPayload.fetch(DeepSeekBalance.self, request: balanceRequest(key: key))
    }
}

struct DeepSeekDescriptor: ProviderDescriptor, AccountBalanceReporting {
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

    func accountBalance(key: String) async -> String? {
        (try? await DeepSeekAPI.fetchBalance(key: key))?.text
    }
}
