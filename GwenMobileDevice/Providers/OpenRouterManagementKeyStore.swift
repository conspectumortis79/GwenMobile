import SwiftUI

@MainActor
final class OpenRouterManagementKeyStore: ObservableObject {
    static let shared = OpenRouterManagementKeyStore()
    static let account = "openrouter_management_api_key"

    @Published private(set) var key: String
    @Published private(set) var hasStoredKey: Bool
    @Published private(set) var problem: String?

    private let store: any KeyStoring
    private let debouncer = KeySaveDebouncer<String>()
    private var slot: KeychainSlot

    init(store: any KeyStoring = KeychainKeyStore()) {
        self.store = store
        let initial = KeychainSlot(store: store, account: Self.account)
        slot = initial
        key = initial.value
        hasStoredKey = initial.isStored
        problem = initial.isBlocked ? L.t("keychain_blocked") : nil
    }

    func reloadBlocked() {
        guard slot.reloadBlocked(from: store, account: Self.account) else { return }
        key = slot.value
        hasStoredKey = slot.isStored
        problem = nil
    }

    func set(_ value: String) {
        slot.set(value)
        key = slot.value
        problem = nil
        scheduleSave()
    }

    func clear() {
        slot.requestClear()
        key = slot.value
        problem = nil
        scheduleSave()
    }

    func flush() {
        debouncer.flush { _ in }
        persist()
    }

    private func scheduleSave() {
        debouncer.schedule(Self.account) { [weak self] _ in
            self?.persist()
        }
    }

    private func persist() {
        let clearing = slot.pendingClear
        switch slot.persist(to: store, account: Self.account) {
        case .untouched:
            return
        case .stored:
            hasStoredKey = slot.isStored
            problem = nil
        case .failed:
            problem = L.t(clearing ? "key_delete_failed" : "key_save_failed")
        }
    }
}
