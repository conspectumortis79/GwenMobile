import GwenMobileKit
import Contacts
import Foundation

struct LiveContactDirectory: ContactDirectory {
    nonisolated(unsafe) static var authorizationStatus: @Sendable () -> CNAuthorizationStatus = {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    nonisolated(unsafe) static var requestAccess: @Sendable () async -> Bool = {
        (try? await CNContactStore().requestAccess(for: .contacts)) ?? false
    }

    func access() async -> ContactAccess {
        let status = Self.authorizationStatus()
        if status == .authorized { return .granted }
        if status == .limited { return .granted }
        guard status == .notDetermined else { return .denied }
        let granted = await Self.requestAccess()
        return granted ? .granted : .denied
    }

    func cards() async throws -> [ContactCard] {
        try await Offload.run { try ContactCardReader.read(from: CNContactStore()) }
    }
}

protocol ContactCardSource {
    func contactGroups() throws -> [(id: String, name: String)]
    func contactMembers(ofGroup id: String) throws -> [CNContact]
    func allContacts() throws -> [CNContact]
}

struct LiveContactCardSource: ContactCardSource {
    let store: CNContactStore

    func contactGroups() throws -> [(id: String, name: String)] {
        try store.groups(matching: nil).map { ($0.identifier, $0.name) }
    }

    func contactMembers(ofGroup id: String) throws -> [CNContact] {
        try store.unifiedContacts(matching: CNContact.predicateForContactsInGroup(withIdentifier: id),
                                  keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor])
    }

    func allContacts() throws -> [CNContact] {
        var result: [CNContact] = []
        try store.enumerateContacts(with: CNContactFetchRequest(keysToFetch: ContactCardReader.keys)) {
            contact, _ in
            result.append(contact)
        }
        return result
    }
}

enum ContactCardReader {
    static var keys: [CNKeyDescriptor] {
        [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactMiddleNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactRelationsKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor,
        ]
    }

    static func read(from store: CNContactStore) throws -> [ContactCard] {
        try read(from: LiveContactCardSource(store: store))
    }

    static func read(from source: any ContactCardSource) throws -> [ContactCard] {
        let groups = try memberships(in: source)
        return try source.allContacts().map { contact in
            ContactCardMapper.card(from: contact, groups: groups[contact.identifier] ?? [])
        }
    }

    static func memberships(in source: any ContactCardSource) throws -> [String: [String]] {
        var found: [String: [String]] = [:]
        for group in try source.contactGroups() {
            let members = try source.contactMembers(ofGroup: group.id)
            for member in members { found[member.identifier, default: []].append(group.name) }
        }
        return found
    }
}
