@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class ProviderKeyVaultTests: XCTestCase {
    private var accounts: [ProviderID: String] {
        [.qwenCloud: "qwen_key", .openAICompatible: "openai_key", .openRouter: "router_key"]
    }

    func testAKeyThatWasNeverEditedStaysUntouchedInTheKeychain() {
        let store = RecordingStore(stored: ["qwen_key": "sk-echt"])
        var vault = ProviderKeyVault(store: store, accounts: accounts)
        XCTAssertEqual(vault.persist(.qwenCloud), .untouched)
        XCTAssertEqual(store.read(account: "qwen_key"), .value("sk-echt"))
        XCTAssertTrue(store.deleteCalls.isEmpty)
    }

    func testABlockedReadLeavesTheStoredKeyWhereItIs() {
        let store = RecordingStore(stored: ["openai_key": "sk-or"])
        store.blocked = ["openai_key"]
        var vault = ProviderKeyVault(store: store, accounts: accounts)
        XCTAssertTrue(vault.hasBlockedEntry)
        XCTAssertEqual(vault.value(for: .openAICompatible), "")
        XCTAssertEqual(vault.persist(.openAICompatible), .untouched)
        XCTAssertEqual(store.read(account: "openai_key"), .blocked(status: RecordingStore.blockedStatus))
    }

    func testABlockedEntryClearsOnceTheUserTypesAKey() {
        let store = RecordingStore(stored: ["openai_key": "sk-or"])
        store.blocked = ["openai_key"]
        var vault = ProviderKeyVault(store: store, accounts: accounts)
        vault.set("sk-neu", for: .openAICompatible)
        XCTAssertEqual(vault.persist(.openAICompatible), .stored)
        XCTAssertFalse(vault.hasBlockedEntry)
        XCTAssertEqual(store.read(account: "openai_key"), .value("sk-neu"))
    }

    func testOnlyAnEditedKeyIsWrittenBack() {
        let store = RecordingStore(stored: ["router_key": "alt"])
        var vault = ProviderKeyVault(store: store, accounts: accounts)
        vault.set("sk-frisch", for: .openRouter)
        XCTAssertEqual(vault.persist(.openRouter), .stored)
        XCTAssertEqual(store.read(account: "router_key"), .value("sk-frisch"))
    }

    func testAnEmptyFieldAloneNeverDeletesTheStoredKey() {
        let store = RecordingStore(stored: ["qwen_key": "sk-echt"])
        var vault = ProviderKeyVault(store: store, accounts: accounts)
        vault.set("", for: .qwenCloud)
        XCTAssertEqual(vault.persist(.qwenCloud), .untouched)
        XCTAssertEqual(store.read(account: "qwen_key"), .value("sk-echt"))
        XCTAssertTrue(store.deleteCalls.isEmpty)
    }

    func testOnlyAnExplicitClearDeletesTheStoredKey() {
        let store = RecordingStore(stored: ["qwen_key": "sk-echt"])
        var vault = ProviderKeyVault(store: store, accounts: accounts)
        vault.requestClear(.qwenCloud)
        XCTAssertEqual(vault.value(for: .qwenCloud), "")
        XCTAssertEqual(vault.persist(.qwenCloud), .stored)
        XCTAssertEqual(store.read(account: "qwen_key"), .absent)
        XCTAssertEqual(store.deleteCalls, ["qwen_key"])
    }

    func testANewKeyAfterClearReplacesThePendingClear() {
        let store = RecordingStore(stored: ["qwen_key": "sk-echt"])
        var vault = ProviderKeyVault(store: store, accounts: accounts)
        vault.requestClear(.qwenCloud)
        vault.set("sk-neu", for: .qwenCloud)
        XCTAssertEqual(vault.persist(.qwenCloud), .stored)
        XCTAssertEqual(store.read(account: "qwen_key"), .value("sk-neu"))
        XCTAssertTrue(store.deleteCalls.isEmpty)
    }

    func testAnEmptySeedValueNeverRemovesAStoredKey() {
        let store = RecordingStore(stored: ["qwen_key": "sk-echt"])
        var vault = ProviderKeyVault(store: store, accounts: accounts)
        vault.seed("", for: .qwenCloud)
        XCTAssertEqual(store.read(account: "qwen_key"), .value("sk-echt"))
        XCTAssertTrue(store.deleteCalls.isEmpty)
    }

    func testASeedValueTravelsIntoTheKeychain() {
        let store = RecordingStore(stored: [:])
        var vault = ProviderKeyVault(store: store, accounts: accounts)
        vault.seed("sk-gesät", for: .qwenCloud)
        XCTAssertEqual(vault.value(for: .qwenCloud), "sk-gesät")
        XCTAssertEqual(store.read(account: "qwen_key"), .value("sk-gesät"))
    }

    func testABlockedReadRecoversOnceTheKeychainUnlocks() {
        let store = RecordingStore(stored: ["openai_key": "sk-or"])
        store.blocked = ["openai_key"]
        var vault = ProviderKeyVault(store: store, accounts: accounts)
        XCTAssertTrue(vault.hasBlockedEntry)
        store.blocked = []
        let recovered = vault.reloadBlocked()
        XCTAssertEqual(recovered, [.openAICompatible])
        XCTAssertFalse(vault.hasBlockedEntry)
        XCTAssertEqual(vault.value(for: .openAICompatible), "sk-or")
    }

    func testAReloadThatStaysBlockedKeepsTheEntryAndTheMarker() {
        let store = RecordingStore(stored: ["openai_key": "sk-or"])
        store.blocked = ["openai_key"]
        var vault = ProviderKeyVault(store: store, accounts: accounts)
        XCTAssertEqual(vault.reloadBlocked(), [])
        XCTAssertTrue(vault.hasBlockedEntry)
        XCTAssertEqual(vault.value(for: .openAICompatible), "")
    }

    func testAReloadLeavesAFreshlyTypedKeyAlone() {
        let store = RecordingStore(stored: ["openai_key": "sk-or"])
        store.blocked = ["openai_key"]
        var vault = ProviderKeyVault(store: store, accounts: accounts)
        vault.set("sk-neu", for: .openAICompatible)
        store.blocked = []
        let recovered = vault.reloadBlocked()
        XCTAssertEqual(recovered, [.openAICompatible])
        XCTAssertFalse(vault.hasBlockedEntry)
        XCTAssertEqual(vault.value(for: .openAICompatible), "sk-neu")
    }

}

private final class RecordingStore: KeyStoring, @unchecked Sendable {
    static let blockedStatus = -25308

    private var values: [String: String]
    var blocked: Set<String> = []
    private(set) var deleteCalls: [String] = []

    init(stored: [String: String]) {
        values = stored
    }

    func read(account: String) -> KeychainRead {
        if blocked.contains(account) { return .blocked(status: Self.blockedStatus) }
        guard let value = values[account], !value.isEmpty else { return .absent }
        return .value(value)
    }

    @discardableResult
    func save(_ value: String, account: String) -> Bool {
        guard !value.isEmpty else { return false }
        values[account] = value
        blocked.remove(account)
        return true
    }

    @discardableResult
    func delete(account: String) -> Bool {
        deleteCalls.append(account)
        values[account] = nil
        blocked.remove(account)
        return true
    }
}
