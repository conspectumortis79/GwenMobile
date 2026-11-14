import Foundation
import Security

enum KeychainInterop {
    nonisolated(unsafe) static var copyMatching: @Sendable ([String: Any]) -> (OSStatus, AnyObject?) = { query in
        var found: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &found)
        return (status, found)
    }

    nonisolated(unsafe) static var updateItem: @Sendable ([String: Any], [String: Any]) -> OSStatus = {
        SecItemUpdate($0 as CFDictionary, $1 as CFDictionary)
    }

    nonisolated(unsafe) static var addItem: @Sendable ([String: Any]) -> OSStatus = {
        SecItemAdd($0 as CFDictionary, nil)
    }

    nonisolated(unsafe) static var deleteItem: @Sendable ([String: Any]) -> OSStatus = {
        SecItemDelete($0 as CFDictionary)
    }
}

enum KeychainStep: String, Sendable {
    case update = "aktualisieren"
    case add = "speichern"
    case delete = "loeschen"
}

enum KeychainOutcome: Equatable, Sendable {
    case done
    case failed(KeychainStep, status: OSStatus)
}

struct KeychainItem: Sendable {
    enum Scope: Sendable {
        case backedUp
        case thisDevice
    }

    let service: String
    let account: String
    let scope: Scope

    var accessible: CFString {
        switch scope {
        case .backedUp: return kSecAttrAccessibleAfterFirstUnlock
        case .thisDevice: return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
    }

    func read(withAttributes: Bool) -> (OSStatus, AnyObject?) {
        var lookup = query
        lookup[kSecReturnData as String] = true
        if withAttributes { lookup[kSecReturnAttributes as String] = true }
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        return KeychainInterop.copyMatching(lookup)
    }

    func write(_ data: Data) -> KeychainOutcome {
        let updated = KeychainInterop.updateItem(query, [kSecValueData as String: data,
                                                         kSecAttrAccessible as String: accessible])
        if updated == errSecSuccess { return .done }
        guard updated == errSecItemNotFound else { return .failed(.update, status: updated) }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = accessible
        let added = KeychainInterop.addItem(add)
        return added == errSecSuccess ? .done : .failed(.add, status: added)
    }

    func delete() -> KeychainOutcome {
        let removed = KeychainInterop.deleteItem(query)
        return removed == errSecSuccess || removed == errSecItemNotFound ? .done : .failed(.delete, status: removed)
    }

    func raiseAccessibility() {
        _ = KeychainInterop.updateItem(query, [kSecAttrAccessible as String: accessible])
    }

    private var query: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if scope == .thisDevice { query[kSecAttrSynchronizable as String] = false }
        return query
    }
}
