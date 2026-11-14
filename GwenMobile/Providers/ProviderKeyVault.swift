import GwenMobileKit
import Foundation

enum KeyPersisted: Equatable {
    case untouched
    case stored
    case failed
}

@MainActor
struct ProviderKeyVault {
    private let store: any KeyStoring
    private let accounts: [ProviderID: String]
    private var values: [ProviderID: String]
    private var touched: Set<ProviderID> = []
    private var pendingClear: Set<ProviderID> = []
    private var blocked: Set<ProviderID> = []
    private var stored: Set<ProviderID> = []

    init(store: any KeyStoring, accounts: [ProviderID: String] = ProviderKeyVault.accountsOfAllProviders()) {
        self.store = store
        self.accounts = accounts
        let read = accounts.mapValues { store.read(account: $0) }
        values = read.mapValues(\.text)
        blocked = Set(read.compactMap { key, outcome in outcome.isBlocked ? key : nil })
        stored = Set(read.compactMap { key, outcome in
            if case .value = outcome { return key }
            return nil
        })
    }

    static func accountsOfAllProviders() -> [ProviderID: String] {
        Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { ($0, $0.descriptor.keychainAccount) })
    }

    var hasBlockedEntry: Bool { !blocked.isEmpty }

    func value(for provider: ProviderID) -> String { values[provider] ?? "" }

    func hasStoredKey(for provider: ProviderID) -> Bool { stored.contains(provider) }

    mutating func set(_ value: String, for provider: ProviderID) {
        guard !value.isEmpty else {
            requestClear(provider)
            return
        }
        values[provider] = value
        pendingClear.remove(provider)
        touched.insert(provider)
    }

    mutating func requestClear(_ provider: ProviderID) {
        values[provider] = ""
        touched.remove(provider)
        pendingClear.insert(provider)
    }

    @discardableResult
    mutating func reloadBlocked() -> Set<ProviderID> {
        guard !blocked.isEmpty else { return [] }
        var recovered: Set<ProviderID> = []
        var stillBlocked: Set<ProviderID> = []
        for provider in blocked {
            guard let account = accounts[provider] else { continue }
            switch store.read(account: account) {
            case .value(let text):
                if !touched.contains(provider) { values[provider] = text }
                stored.insert(provider)
                recovered.insert(provider)
            case .absent:
                stored.remove(provider)
                recovered.insert(provider)
            case .blocked:
                stillBlocked.insert(provider)
            }
        }
        blocked = stillBlocked
        return recovered
    }

    mutating func seed(_ value: String, for provider: ProviderID) {
        values[provider] = value
        blocked.remove(provider)
        guard !value.isEmpty, let account = accounts[provider] else { return }
        if store.save(value, account: account) { stored.insert(provider) }
    }

    @discardableResult
    mutating func persist(_ provider: ProviderID) -> KeyPersisted {
        guard let account = accounts[provider] else { return .untouched }
        if pendingClear.contains(provider) {
            guard store.delete(account: account) else { return .failed }
            pendingClear.remove(provider)
            blocked.remove(provider)
            stored.remove(provider)
            return .stored
        }
        guard touched.contains(provider) else { return .untouched }
        let value = values[provider] ?? ""
        guard !value.isEmpty else { return .untouched }
        guard store.save(value, account: account) else { return .failed }
        touched.remove(provider)
        blocked.remove(provider)
        stored.insert(provider)
        return .stored
    }
}
