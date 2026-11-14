import GwenMobileKit

extension AppSettings {
    var apiKey: String {
        get { key(for: provider) }
        set { setKey(newValue, for: provider) }
    }

    func setKey(_ value: String, for provider: ProviderID) {
        vault.set(value, for: provider)
        objectWillChange.send()
        Self.scheduleKeySave(for: provider)
    }

    func clearKey(for provider: ProviderID) {
        vault.requestClear(provider)
        objectWillChange.send()
        Self.scheduleKeySave(for: provider)
    }

    func hasStoredKey(for provider: ProviderID) -> Bool {
        vault.hasStoredKey(for: provider)
    }

    func baseURL(for provider: ProviderID) -> String {
        provider.descriptor.baseURL(connections)
    }

    func key(for provider: ProviderID) -> String {
        vault.value(for: provider)
    }

    func isConfigured(for provider: ProviderID) -> Bool {
        if provider == .local {
            let selected = profile(of: .local).chatModel
            return !selected.isEmpty && LocalModelFiles().isInstalled(selected)
        }
        return provider.descriptor.isConfigured(connections, key: key(for: provider))
    }
}
