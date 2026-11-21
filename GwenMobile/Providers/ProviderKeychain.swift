import GwenMobileKit
import Foundation
import Security

enum KeychainRead: Equatable, Sendable {
    case value(String)
    case absent
    case blocked(status: Int)

    var text: String {
        switch self {
        case .value(let stored): return stored
        case .absent, .blocked: return ""
        }
    }

    var isBlocked: Bool {
        if case .blocked = self { return true }
        return false
    }
}

protocol KeyStoring: Sendable {
    func read(account: String) -> KeychainRead
    @discardableResult func save(_ value: String, account: String) -> Bool
    @discardableResult func delete(account: String) -> Bool
}

struct KeychainKeyStore: KeyStoring {
    let service: String

    init(service: String = "GwenMobile") {
        self.service = service
    }

    func read(account: String) -> KeychainRead {
        let entry = item(account)
        let (status, found) = entry.read(withAttributes: true)
        switch status {
        case errSecSuccess:
            guard let attributes = found as? [String: Any],
                  let data = attributes[kSecValueData as String] as? Data else { return .absent }
            if (attributes[kSecAttrAccessible as String] as? String) != (entry.accessible as String) {
                entry.raiseAccessibility()
            }
            return .value(String(decoding: data, as: UTF8.self))
        case errSecItemNotFound:
            return .absent
        default:
            flowLog.error("KEYSCHLUESSEL lesen konto=\(account, privacy: .public) status=\(Int(status))")
            return .blocked(status: Int(status))
        }
    }

    @discardableResult
    func save(_ value: String, account: String) -> Bool {
        guard !value.isEmpty else { return false }
        return succeeded(item(account).write(Data(value.utf8)), account: account)
    }

    @discardableResult
    func delete(account: String) -> Bool {
        succeeded(item(account).delete(), account: account)
    }

    private func succeeded(_ outcome: KeychainOutcome, account: String) -> Bool {
        guard case .failed(let step, let status) = outcome else { return true }
        flowLog.error("KEYSCHLUESSEL \(step.rawValue, privacy: .public) konto=\(account, privacy: .public) status=\(Int(status))")
        return false
    }

    private func item(_ account: String) -> KeychainItem {
        KeychainItem(service: service, account: account, scope: .backedUp)
    }
}
