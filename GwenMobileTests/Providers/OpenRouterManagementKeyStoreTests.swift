@testable import GwenMobileFeatureCore
import XCTest

@MainActor
final class OpenRouterManagementKeyStoreTests: XCTestCase {
    func testTheManagementKeyIsSavedAndCleared() {
        let keychain = MemoryKeyStore()
        let store = OpenRouterManagementKeyStore(store: keychain)
        XCTAssertFalse(store.hasStoredKey)

        store.set("sk-or-management")
        store.flush()
        XCTAssertEqual(keychain.read(account: OpenRouterManagementKeyStore.account), .value("sk-or-management"))
        XCTAssertTrue(store.hasStoredKey)

        store.clear()
        store.flush()
        XCTAssertEqual(keychain.read(account: OpenRouterManagementKeyStore.account), .absent)
        XCTAssertFalse(store.hasStoredKey)
    }

    func testAnExistingManagementKeyIsLoaded() {
        let keychain = MemoryKeyStore()
        keychain.save("sk-or-existing", account: OpenRouterManagementKeyStore.account)
        let store = OpenRouterManagementKeyStore(store: keychain)
        XCTAssertEqual(store.key, "sk-or-existing")
        XCTAssertTrue(store.hasStoredKey)
        XCTAssertNil(store.problem)
    }

    func testErasingTheFieldRemovesTheStoredManagementKey() {
        let keychain = MemoryKeyStore()
        keychain.save("sk-or-existing", account: OpenRouterManagementKeyStore.account)
        let store = OpenRouterManagementKeyStore(store: keychain)
        store.set("")
        store.flush()
        XCTAssertEqual(keychain.read(account: OpenRouterManagementKeyStore.account), .absent)
        XCTAssertFalse(store.hasStoredKey)
    }

    func testBlockedManagementKeyRecoversWhenKeychainUnlocks() {
        let keychain = BlockedManagementKeyStore(stored: "sk-or-locked")
        let store = OpenRouterManagementKeyStore(store: keychain)
        XCTAssertEqual(store.key, "")
        XCTAssertFalse(store.hasStoredKey)
        XCTAssertNotNil(store.problem)
        store.reloadBlocked()
        XCTAssertEqual(store.key, "")
        keychain.blocked = false
        store.reloadBlocked()
        XCTAssertEqual(store.key, "sk-or-locked")
        XCTAssertTrue(store.hasStoredKey)
        XCTAssertNil(store.problem)
    }

    func testReloadBlockedDoesNotResurrectAClearedManagementKey() {
        let keychain = BlockedManagementKeyStore(stored: "sk-or-locked")
        let store = OpenRouterManagementKeyStore(store: keychain)
        store.clear()
        keychain.blocked = false
        store.reloadBlocked()
        XCTAssertEqual(store.key, "")
    }
}

private final class BlockedManagementKeyStore: KeyStoring, @unchecked Sendable {
    var stored: String?
    var blocked = true

    init(stored: String?) {
        self.stored = stored
    }

    func read(account: String) -> KeychainRead {
        if blocked { return .blocked(status: -25308) }
        guard let stored, !stored.isEmpty else { return .absent }
        return .value(stored)
    }

    @discardableResult
    func save(_ value: String, account: String) -> Bool {
        stored = value
        return true
    }

    @discardableResult
    func delete(account: String) -> Bool {
        stored = nil
        return true
    }
}
