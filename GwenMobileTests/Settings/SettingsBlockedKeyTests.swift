@testable import GwenMobileFeatureCore
@testable import GwenMobileDevice
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
        settings.vault = ProviderKeyVault(store: store)
        XCTAssertTrue(settings.vault.hasBlockedEntry)
        settings.keychainProblem = L.t("keychain_blocked")
        store.blocked = false
        settings.reloadBlockedKeys()
        XCTAssertNil(settings.keychainProblem)
        XCTAssertEqual(settings.vault.value(for: .qwenCloud), "sk-frei")
    }
}
