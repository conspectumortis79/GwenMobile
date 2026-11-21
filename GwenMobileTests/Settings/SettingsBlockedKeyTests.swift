@testable import GwenMobileFeatureCore
import GwenMobileKit
import XCTest

private final class BlockedKeyStore: KeyStoring, @unchecked Sendable {
    var blocked = true
    let value: String

    init(value: String) { self.value = value }

    func read(account: String) -> KeychainRead {
        blocked ? .blocked(status: 1) : .value(value)
    }

    @discardableResult func save(_ value: String, account: String) -> Bool { true }
    @discardableResult func delete(account: String) -> Bool { true }
}

@MainActor
final class SettingsBlockedKeyTests: GwenTestCase {
    func testTheBlockedKeyIsRecoveredAndTheProblemCleared() {
        let store = BlockedKeyStore(value: "sk-frei")
        let settings = AppSettings.shared
        let fallback = settings.vault
        settings.vault = ProviderKeyVault(store: store)
        defer { settings.vault = fallback }
        XCTAssertTrue(settings.vault.hasBlockedEntry)
        settings.keychainProblem = L.t("keychain_blocked")
        store.blocked = false
        settings.reloadBlockedKeys()
        XCTAssertNil(settings.keychainProblem)
        XCTAssertEqual(settings.vault.value(for: .qwenCloud), "sk-frei")
    }

    func testTheBlockedKeyProblemStillClearsAfterALanguageSwitch() {
        let store = BlockedKeyStore(value: "sk-frei")
        let settings = AppSettings.shared
        let fallback = settings.vault
        let previousLanguage = settings.language
        settings.vault = ProviderKeyVault(store: store)
        defer {
            settings.vault = fallback
            settings.language = previousLanguage
        }
        settings.language = .de
        settings.keychainProblem = L.t("keychain_blocked")
        settings.language = .en
        store.blocked = false
        settings.reloadBlockedKeys()
        XCTAssertNil(settings.keychainProblem)
    }
}
