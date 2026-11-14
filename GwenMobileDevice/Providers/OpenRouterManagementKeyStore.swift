import SwiftUI

@MainActor
final class OpenRouterManagementKeyStore: ObservableObject {
    static let shared = OpenRouterManagementKeyStore()
    static let account = "openrouter_management_api_key"

    @Published private(set) var key: String
    @Published private(set) var hasStoredKey: Bool
    @Published private(set) var problem: String?

    private let store: any KeyStoring
    private var saveTask: Task<Void, Never>?
    private var touched = false
    private var pendingClear = false

    init(store: any KeyStoring = KeychainKeyStore()) {
        self.store = store
        switch store.read(account: Self.account) {
        case .value(let text):
            key = text
            hasStoredKey = true
            problem = nil
        case .absent:
            key = ""
            hasStoredKey = false
            problem = nil
        case .blocked:
            key = ""
            hasStoredKey = false
            problem = L.t("keychain_blocked")
        }
    }

    func set(_ value: String) {
        guard !value.isEmpty else {
            clear()
            return
        }
        key = value
        touched = true
        pendingClear = false
        problem = nil
        scheduleSave()
    }

    func clear() {
        key = ""
        touched = false
        pendingClear = true
        problem = nil
        scheduleSave()
    }

    func flush() {
        saveTask?.cancel()
        saveTask = nil
        persist()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            persist()
        }
    }

    private func persist() {
        guard touched || pendingClear else { return }
        if pendingClear {
            if store.delete(account: Self.account) {
                hasStoredKey = false
                pendingClear = false
                problem = nil
            } else {
                problem = L.t("key_delete_failed")
            }
            return
        }
        guard !key.isEmpty else { return }
        if store.save(key, account: Self.account) {
            hasStoredKey = true
            touched = false
            problem = nil
        } else {
            problem = L.t("key_save_failed")
        }
    }
}
