import Foundation

extension AppSettings {
    func connectionChanged() {
        HTTP.decorator.set(descriptor.requestDecorator(connections))
    }

    func store<Value: Encodable>(_ value: Value, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        d.set(data, forKey: key)
    }

    static func decode<Value: Decodable>(_ type: Value.Type, _ data: Data?) -> Value? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func scheduleKeySave(for provider: ProviderID) {
        keySaveDebouncer.schedule(provider) { shared.persistKey(for: $0) }
    }

    static func flushKeySave() {
        keySaveDebouncer.flush { shared.persistKey(for: $0) }
    }

    func reloadBlockedKeys() {
        guard vault.hasBlockedEntry else { return }
        let recovered = vault.reloadBlocked()
        guard !recovered.isEmpty, !vault.hasBlockedEntry else { return }
        if let problem = keychainProblem,
           L.strings["keychain_blocked"]?.values.contains(problem) == true {
            keychainProblem = nil
        }
    }

    func persistKey(for provider: ProviderID) {
        let outcome = vault.persist(provider)
        objectWillChange.send()
        switch outcome {
        case .untouched: return
        case .stored: keychainProblem = nil
        case .failed: keychainProblem = L.t("key_save_failed")
        }
    }
}
