import GwenMobileKit
import Contacts
import Foundation

enum ContactCardMapper {
    static let relations: [String: ContactRelation] = [
        CNLabelContactRelationMother: .mother,
        CNLabelContactRelationFather: .father,
        CNLabelContactRelationParent: .parent,
        CNLabelContactRelationSister: .sister,
        CNLabelContactRelationYoungerSister: .sister,
        CNLabelContactRelationElderSister: .sister,
        CNLabelContactRelationBrother: .brother,
        CNLabelContactRelationYoungerBrother: .brother,
        CNLabelContactRelationElderBrother: .brother,
        CNLabelContactRelationSibling: .sibling,
        CNLabelContactRelationDaughter: .daughter,
        CNLabelContactRelationSon: .son,
        CNLabelContactRelationChild: .child,
        CNLabelContactRelationWife: .wife,
        CNLabelContactRelationHusband: .husband,
        CNLabelContactRelationSpouse: .spouse,
        CNLabelContactRelationPartner: .partner,
        CNLabelContactRelationGrandmother: .grandmother,
        CNLabelContactRelationGrandmotherMothersMother: .grandmother,
        CNLabelContactRelationGrandmotherFathersMother: .grandmother,
        CNLabelContactRelationGrandfather: .grandfather,
        CNLabelContactRelationGrandfatherMothersFather: .grandfather,
        CNLabelContactRelationGrandfatherFathersFather: .grandfather,
        CNLabelContactRelationGrandparent: .grandparent,
        CNLabelContactRelationAunt: .aunt,
        CNLabelContactRelationUncle: .uncle,
        CNLabelContactRelationCousin: .cousin,
        CNLabelContactRelationFriend: .friend,
        CNLabelContactRelationAssistant: .assistant,
        CNLabelContactRelationManager: .manager,
    ]

    static let phoneKinds: [String: PhoneKind] = [
        CNLabelPhoneNumberMobile: .mobile,
        CNLabelPhoneNumberiPhone: .mobile,
        CNLabelPhoneNumberMain: .main,
        CNLabelHome: .home,
        CNLabelWork: .work,
    ]

    static let notForCalls: Set<String> = [
        CNLabelPhoneNumberHomeFax,
        CNLabelPhoneNumberWorkFax,
        CNLabelPhoneNumberOtherFax,
        CNLabelPhoneNumberPager,
    ]

    static func card(from contact: CNContact, groups: [String]) -> ContactCard {
        let parts = [contact.givenName, contact.middleName, contact.familyName, contact.nickname,
                     contact.organizationName].filter { !$0.isEmpty }
        let formatted = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
        let name = formatted.isEmpty ? (parts.first ?? "") : formatted
        return ContactCard(id: contact.identifier, name: name, nameParts: parts, groups: groups,
                           ties: contact.contactRelations.map(tie),
                           phones: contact.phoneNumbers.compactMap(phone),
                           birthday: contact.birthday)
    }

    static func tie(_ entry: CNLabeledValue<CNContactRelation>) -> ContactTie {
        let label = entry.label ?? ""
        return ContactTie(relation: relations[label], label: readable(label), name: entry.value.name)
    }

    static func phone(_ entry: CNLabeledValue<CNPhoneNumber>) -> ContactPhone? {
        let label = entry.label ?? ""
        guard !notForCalls.contains(label) else { return nil }
        return ContactPhone(kind: phoneKinds[label] ?? .other, label: readable(label),
                            number: entry.value.stringValue)
    }

    static func readable(_ label: String) -> String {
        guard !label.isEmpty else { return "" }
        return CNLabeledValue<NSString>.localizedString(forLabel: label)
    }
}
