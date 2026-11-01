import GwenMobileKit
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
        if let pending = pendingKeySave, pending.provider != provider { flushKeySave() }
        pendingKeySave?.task.cancel()
        let task = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            pendingKeySave = nil
            shared.persistKey(for: provider)
        }
        pendingKeySave = (provider, task)
    }

    static func flushKeySave() {
        guard let pending = pendingKeySave else { return }
        pendingKeySave = nil
        pending.task.cancel()
        shared.persistKey(for: pending.provider)
    }

    func reloadBlockedKeys() {
        guard vault.hasBlockedEntry else { return }
        let recovered = vault.reloadBlocked()
        guard !recovered.isEmpty, !vault.hasBlockedEntry else { return }
        if keychainProblem == L.t("keychain_blocked") { keychainProblem = nil }
    }

    func persistKey(for provider: ProviderID) {
        switch vault.persist(provider) {
        case .untouched: return
        case .stored: keychainProblem = nil
        case .failed: keychainProblem = L.t("key_save_failed")
        }
    }
}
