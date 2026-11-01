import GwenMobileKit
import Foundation

struct ContactPhone: Equatable, Sendable {
    let kind: PhoneKind
    let label: String
    let number: String

    var dialable: DialNumber? { DialNumber(number) }
}

struct ContactTie: Equatable, Sendable {
    let relation: ContactRelation?
    let label: String
    let name: String
}

struct ContactCard: Equatable, Sendable {
    let id: String
    let name: String
    let nameParts: [String]
    var groups: [String] = []
    var ties: [ContactTie] = []
    var phones: [ContactPhone] = []
    var birthday: DateComponents? = nil
}

enum ContactAccess: Equatable, Sendable {
    case granted
    case denied
}

protocol ContactDirectory: Sendable {
    func access() async -> ContactAccess
    func cards() async throws -> [ContactCard]
}
