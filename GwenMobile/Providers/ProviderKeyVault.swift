import Foundation

enum KeyPersisted: Equatable {
    case untouched
    case stored
    case failed
}

@MainActor
struct KeychainSlot {
    private(set) var value: String
    private(set) var isStored: Bool
    private(set) var isBlocked: Bool
    private(set) var touched = false
    private(set) var pendingClear = false

    init(store: any KeyStoring, account: String) {
        let read = store.read(account: account)
        value = read.text
        isBlocked = read.isBlocked
        if case .value = read {
            isStored = true
        } else {
            isStored = false
        }
    }

    mutating func set(_ newValue: String) {
        guard !newValue.isEmpty else {
            requestClear()
            return
        }
        value = newValue
        pendingClear = false
        touched = true
    }

    mutating func requestClear() {
        value = ""
        touched = false
        pendingClear = true
    }

    @discardableResult
    mutating func reloadBlocked(from store: any KeyStoring, account: String) -> Bool {
        guard isBlocked else { return false }
        switch store.read(account: account) {
        case .value(let text):
            if !touched, !pendingClear { value = text }
            isStored = true
            isBlocked = false
            return true
        case .absent:
            isStored = false
            isBlocked = false
            return true
        case .blocked:
            return false
        }
    }

    #if DEBUG
    mutating func seed(_ newValue: String, in store: any KeyStoring, account: String) {
        value = newValue
        isBlocked = false
        guard !newValue.isEmpty else { return }
        if store.save(newValue, account: account) { isStored = true }
    }
    #endif

    @discardableResult
    mutating func persist(to store: any KeyStoring, account: String) -> KeyPersisted {
        if pendingClear {
            guard store.delete(account: account) else { return .failed }
            pendingClear = false
            isBlocked = false
            isStored = false
            return .stored
        }
        guard touched, !value.isEmpty else { return .untouched }
        guard store.save(value, account: account) else { return .failed }
        touched = false
        isBlocked = false
        isStored = true
        return .stored
    }
}

@MainActor
final class KeySaveDebouncer<Key: Equatable> {
    static var defaultDelay: Duration { .milliseconds(600) }

    private let delay: Duration
    private var pending: (key: Key, task: Task<Void, Never>)?

    init(delay: Duration = KeySaveDebouncer.defaultDelay) {
        self.delay = delay
    }

    func schedule(_ key: Key, save: @escaping @MainActor (Key) -> Void) {
        if let pending, pending.key != key { flush(using: save) }
        pending?.task.cancel()
        let delay = self.delay
        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.pending = nil
            save(key)
        }
        pending = (key, task)
    }

    func flush(using save: @MainActor (Key) -> Void) {
        guard let pending else { return }
        self.pending = nil
        pending.task.cancel()
        save(pending.key)
    }
}

@MainActor
struct ProviderKeyVault {
    private let store: any KeyStoring
    private let accounts: [ProviderID: String]
    private var slots: [ProviderID: KeychainSlot]

    init(store: any KeyStoring, accounts: [ProviderID: String] = ProviderKeyVault.accountsOfAllProviders()) {
        self.store = store
        self.accounts = accounts
        slots = accounts.mapValues { KeychainSlot(store: store, account: $0) }
    }

    static func accountsOfAllProviders() -> [ProviderID: String] {
        Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { ($0, $0.descriptor.keychainAccount) })
    }

    var hasBlockedEntry: Bool { slots.values.contains(where: \.isBlocked) }

    func value(for provider: ProviderID) -> String { slots[provider]?.value ?? "" }

    func hasStoredKey(for provider: ProviderID) -> Bool { slots[provider]?.isStored ?? false }

    mutating func set(_ value: String, for provider: ProviderID) {
        slots[provider]?.set(value)
    }

    mutating func requestClear(_ provider: ProviderID) {
        slots[provider]?.requestClear()
    }

    @discardableResult
    mutating func reloadBlocked() -> Set<ProviderID> {
        let store = self.store
        var recovered: Set<ProviderID> = []
        for (provider, account) in accounts where slots[provider]?.reloadBlocked(from: store, account: account) == true {
            recovered.insert(provider)
        }
        return recovered
    }

    #if DEBUG
    mutating func seed(_ value: String, for provider: ProviderID) {
        guard let account = accounts[provider] else { return }
        let store = self.store
        slots[provider]?.seed(value, in: store, account: account)
    }
    #endif

    @discardableResult
    mutating func persist(_ provider: ProviderID) -> KeyPersisted {
        guard let account = accounts[provider], var slot = slots[provider] else { return .untouched }
        let outcome = slot.persist(to: store, account: account)
        slots[provider] = slot
        return outcome
    }
}
