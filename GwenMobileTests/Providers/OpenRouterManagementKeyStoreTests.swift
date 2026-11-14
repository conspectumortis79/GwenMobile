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
}
