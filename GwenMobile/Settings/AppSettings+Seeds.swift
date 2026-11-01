import GwenMobileKit
#if DEBUG
import Foundation

extension AppSettings {
    func importProviderSeed() {
        let url = StoragePaths().providerSeed
        guard let seed = SettingsSeed.load(from: url) else { return }
        connections = seed.applied(to: connections)
        store(connections, forKey: SettingsKey.providerConnections)
        for (target, value) in seed.keys ?? [:] {
            vault.seed(value, for: target)
        }
        if let target = seed.provider {
            provider = target
            d.set(provider.rawValue, forKey: SettingsKey.provider)
        }
        SettingsSeed.consume(url)
        flowLog.info("SEED anbieter=\(self.provider.rawValue, privacy: .public) uebernommen")
    }

    func importSeedFile() {
        guard key(for: .qwenCloud).isEmpty else { return }
        let url = StoragePaths().apiKeySeed
        guard let data = try? Data(contentsOf: url),
              let key = String(data: data, encoding: .utf8)?
                .trimmed, !key.isEmpty else { return }
        vault.seed(key, for: .qwenCloud)
        try? FileManager.default.removeItem(at: url)
    }
}
#endif
