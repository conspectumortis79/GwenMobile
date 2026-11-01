import GwenMobileKit
import Foundation

struct ProviderSeed: Decodable, Equatable {
    var provider: ProviderID?
    var qwenCloud: QwenCloudConfig?
    var openAICompatible: OpenAICompatibleConfig?
    var openRouter: OpenRouterConfig?
    var keys: [ProviderID: String]?

    func applied(to connections: ProviderConnections) -> ProviderConnections {
        var merged = connections
        if let qwenCloud { merged.qwenCloud = qwenCloud }
        if let openAICompatible { merged.openAICompatible = openAICompatible }
        if let openRouter { merged.openRouter = openRouter }
        return merged
    }
}

enum SettingsSeed {
    static func load(from url: URL) -> ProviderSeed? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ProviderSeed.self, from: data)
    }

    static func consume(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
