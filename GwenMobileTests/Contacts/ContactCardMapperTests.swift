@testable import GwenMobileFeatureCore
import Contacts
import XCTest
import GwenMobileKit

final class ContactCardMapperTests: GwenTestCase {
    func testAnEmptyContactStaysWithoutAName() {
        let contact = CNMutableContact()
        let card = ContactCardMapper.card(from: contact, groups: [])
        XCTAssertEqual(card.name, "")
        XCTAssertTrue(card.nameParts.isEmpty)
    }

    func testANameWithoutALabelKeepsTheWrittenName() throws {
        let contact = CNMutableContact()
        contact.givenName = "Maria"
        contact.familyName = "Probemuster"
        let card = ContactCardMapper.card(from: contact, groups: ["Familie"])
        XCTAssertEqual(card.name, "Maria Probemuster")
        XCTAssertEqual(card.groups, ["Familie"])
    }

    func testEntriesWithoutALabelStayReadable() throws {
        let relation = CNLabeledValue(label: nil, value: CNContactRelation(name: "Mutter"))
        let tie = ContactCardMapper.tie(relation)
        XCTAssertEqual(tie.name, "Mutter")
        XCTAssertEqual(tie.label, "")
        let phone = CNLabeledValue(label: nil, value: CNPhoneNumber(stringValue: "030 1234567"))
        let mapped = try XCTUnwrap(ContactCardMapper.phone(phone))
        XCTAssertEqual(mapped.label, "")
        XCTAssertEqual(mapped.kind, .other)
    }

    func testKnownLabelsAreLocalizedAndJunkLabelsStayAsWritten() {
        XCTAssertEqual(ContactCardMapper.readable(""), "")
        XCTAssertEqual(ContactCardMapper.readable(CNLabelHome),
                       CNLabeledValue<NSString>.localizedString(forLabel: CNLabelHome))
        XCTAssertFalse(ContactCardMapper.readable(CNLabelHome).isEmpty)
        XCTAssertEqual(ContactCardMapper.readable("gibt_es_nicht"), "gibt_es_nicht")
    }

    func testFaxNumbersAreNotCallable() {
        let fax = CNLabeledValue(label: CNLabelPhoneNumberHomeFax,
                                 value: CNPhoneNumber(stringValue: "030 1234567"))
        XCTAssertNil(ContactCardMapper.phone(fax))
    }
}
