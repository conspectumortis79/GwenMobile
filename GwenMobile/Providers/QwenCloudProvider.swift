import GwenMobileKit
import Foundation

enum QwenBilling: String, CaseIterable, Identifiable, Codable, Sendable {
    case tokenPlan
    case payAsYouGo

    var id: String { rawValue }

    var labelKey: String {
        switch self {
        case .tokenPlan: return "qwen_billing_token_plan"
        case .payAsYouGo: return "qwen_billing_payg"
        }
    }

    nonisolated var label: String { L.t(labelKey) }
    var hasRegions: Bool { self == .payAsYouGo }
}

enum QwenRegion: String, CaseIterable, Identifiable, Codable, Sendable {
    case international
    case us
    case china
    case eu

    var id: String { rawValue }

    var labelKey: String {
        switch self {
        case .international: return "qwen_region_intl"
        case .us: return "qwen_region_us"
        case .china: return "qwen_region_cn"
        case .eu: return "qwen_region_eu"
        }
    }

    nonisolated var label: String { L.t(labelKey) }
    var needsWorkspace: Bool { self == .eu }
}

struct QwenCloudConfig: Codable, Equatable, Sendable {
    var billing: QwenBilling = .tokenPlan
    var region: QwenRegion = .international
    var workspace = ""

    var baseURL: String { QwenEndpoints.url(for: self) }
    var showsRegion: Bool { billing.hasRegions }
    var showsWorkspace: Bool { billing.hasRegions && region.needsWorkspace }
    var isComplete: Bool { !showsWorkspace || !workspace.trimmingCharacters(in: .whitespaces).isEmpty }
}

enum QwenEndpoints {
    static let tokenPlan = "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1"
    static let workspacePlaceholder = "<WorkspaceId>"
    private static let euSuffix = ".eu-central-1.maas.aliyuncs.com/compatible-mode/v1"

    static func url(for config: QwenCloudConfig) -> String {
        guard config.billing.hasRegions else { return tokenPlan }
        return url(for: config.region, workspace: config.workspace)
    }

    static func url(for region: QwenRegion, workspace: String) -> String {
        switch region {
        case .international: return "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
        case .us: return "https://dashscope-us.aliyuncs.com/compatible-mode/v1"
        case .china: return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .eu:
            let id = workspace.trimmingCharacters(in: .whitespaces)
            return "https://" + (id.isEmpty ? workspacePlaceholder : id) + euSuffix
        }
    }

    static func config(matching url: String) -> QwenCloudConfig? {
        let trimmed = HTTP.root(url)
        if trimmed == tokenPlan { return QwenCloudConfig(billing: .tokenPlan) }
        for region in QwenRegion.allCases where !region.needsWorkspace {
            if trimmed == self.url(for: region, workspace: "") {
                return QwenCloudConfig(billing: .payAsYouGo, region: region)
            }
        }
        guard trimmed.hasPrefix("https://"), trimmed.hasSuffix(euSuffix) else { return nil }
        let host = trimmed.dropFirst("https://".count).dropLast(euSuffix.count)
        guard !host.isEmpty, !host.contains("/") else { return nil }
        let workspace = host == workspacePlaceholder ? "" : String(host)
        return QwenCloudConfig(billing: .payAsYouGo, region: .eu, workspace: workspace)
    }
}

struct QwenCloudDescriptor: ProviderDescriptor {
    let id = ProviderID.qwenCloud
    let glyph = ProviderGlyph(text: "Q", red: 0.38, green: 0.37, blue: 1.0)
    let capabilities = ProviderCapabilities(chat: .available, vision: .available, image: .available,
                                            video: .available, videoGeneration: .available)
    let defaultProfile = ProviderProfile()
    let thinkingEncoding = ThinkingEncoding.dashScope
    var modelDiscoverer: any ModelDiscovering { CapabilityProber.dashScope }
    var imageBackend: (any ImageGenerating)? { DashScopeImageBackend() }
    var videoGenerationBackend: (any VideoGenerating)? { QwenVideoBackend() }
    let keychainAccount = "qwencloud_api_key"
    let consoleLink: URL? = URL(string: "https://home.qwencloud.com/api-keys")

    var consoleLinkTitle: String { L.t("create_key") }
    var title: String { L.t("provider_qwen_title") }
    var subtitle: String { L.t("provider_qwen_subtitle") }
    var footer: String { L.t("qwen_footer") }
    var modelsFooter: String { L.t("models_footer_qwen") }

    func baseURL(_ connections: ProviderConnections) -> String {
        connections.qwenCloud.baseURL
    }

    func isConfigured(_ connections: ProviderConnections, key: String) -> Bool {
        !key.isEmpty && connections.qwenCloud.isComplete
    }

    func usesPresetURL(_ connections: ProviderConnections) -> Bool {
        !connections.qwenCloud.showsWorkspace
    }
}
