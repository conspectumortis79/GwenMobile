@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class ContactMatchingTests: XCTestCase {
    private func phone(_ kind: PhoneKind, _ label: String, _ number: String) -> ContactPhone {
        ContactPhone(kind: kind, label: label, number: number)
    }

    private func number(_ raw: String) -> DialNumber {
        DialNumber(raw)!
    }

    private var owner: ContactCard {
        ContactCard(id: "ich", name: "Gwen Nutzer", nameParts: ["Gwen", "Nutzer"],
                    ties: [ContactTie(relation: .mother, label: "Mutter", name: "Maria Muster")])
    }

    private var mother: ContactCard {
        ContactCard(id: "mutter", name: "Maria Muster", nameParts: ["Maria", "Muster"], groups: ["Familie"],
                    phones: [phone(.home, "Privat", "+49 30 1111111"), phone(.mobile, "Mobil", "+49 170 2222222")])
    }

    private func peter(_ family: String, _ digits: String, groups: [String] = []) -> ContactCard {
        ContactCard(id: "peter-\(family)", name: "Peter \(family)", nameParts: ["Peter", family], groups: groups,
                    phones: [phone(.mobile, "Mobil", digits)])
    }

    private func resolve(_ request: ContactRequest, _ cards: [ContactCard]) -> ContactResolution {
        ContactMatching.resolve(request, in: cards)
    }

    func testTheMotherOfTheOwnCardIsCalledOnHerMobile() {
        let request = ContactRequest(person: "Mutter", group: "Familie", relation: .mother)
        XCTAssertEqual(resolve(request, [owner, mother]),
                       .unique(CallTarget(name: "Maria Muster", label: "Mobil", number: number("+491702222222")), .none))
    }

    func testTheRelationLabelOfTheDeviceFindsTheMotherEvenWithoutTheRelationField() {
        XCTAssertEqual(resolve(ContactRequest(person: "Mutter"), [owner, mother]),
                       .unique(CallTarget(name: "Maria Muster", label: "Mobil", number: number("+491702222222")), .none))
    }

    func testAContactSavedUnderItsNicknameIsFoundByIt() {
        let mama = ContactCard(id: "mama", name: "Maria Muster", nameParts: ["Maria", "Muster", "Mama"],
                               phones: [phone(.mobile, "Mobil", "+49 170 2222222")])
        XCTAssertEqual(resolve(ContactRequest(person: "Mama", relation: .mother), [mama]),
                       .unique(CallTarget(name: "Maria Muster", label: "Mobil", number: number("+491702222222")), .none))
    }

    func testTheAskedKindOfNumberWins() {
        let request = ContactRequest(person: "Maria Muster", numberKind: .home)
        XCTAssertEqual(resolve(request, [mother]),
                       .unique(CallTarget(name: "Maria Muster", label: "Privat", number: number("+49301111111")), .none))
    }

    func testAMissingKindFallsBackToTheBestOtherNumber() {
        let request = ContactRequest(person: "Maria Muster", numberKind: .work)
        XCTAssertEqual(resolve(request, [mother]),
                       .unique(CallTarget(name: "Maria Muster", label: "Mobil", number: number("+491702222222")), .none))
    }

    func testTwoPetersAreNeverGuessed() {
        XCTAssertEqual(resolve(ContactRequest(person: "Peter"), [peter("Alpha", "0170 1"), peter("Beta", "0170 2")]),
                       .ambiguous(["Peter Alpha", "Peter Beta"]))
    }

    func testTheGroupNarrowsTwoPetersToOne() {
        let cards = [peter("Alpha", "0170 1"), peter("Beta", "0170 2", groups: ["Arbeit"])]
        XCTAssertEqual(resolve(ContactRequest(person: "Peter", group: "arbeit"), cards),
                       .unique(CallTarget(name: "Peter Beta", label: "Mobil", number: number("01702")), .none))
    }

    func testAnUnknownGroupIsNamedButDoesNotBlockTheCall() {
        XCTAssertEqual(resolve(ContactRequest(person: "Maria Muster", group: "Verein"), [mother]),
                       .unique(CallTarget(name: "Maria Muster", label: "Mobil", number: number("+491702222222")),
                               .missing("Verein")))
    }

    func testAContactOutsideTheNamedGroupIsStillFoundAndTheNoteSaysSo() {
        XCTAssertEqual(resolve(ContactRequest(person: "Peter Alpha", group: "Familie"), [mother, peter("Alpha", "0170 1")]),
                       .unique(CallTarget(name: "Peter Alpha", label: "Mobil", number: number("01701")),
                               .outside("Familie")))
    }

    func testAHeardSlipIsOnlyOfferedAndNeverDialled() {
        let anja = ContactCard(id: "anja", name: "Anja Beispiel", nameParts: ["Anja", "Beispiel"],
                               phones: [phone(.mobile, "Mobil", "0170 3")])
        XCTAssertEqual(resolve(ContactRequest(person: "Anna Beispiel"), [anja]), .unsure(["Anja Beispiel"]))
    }

    func testAnExactNameBeatsASimilarOne() {
        let anna = ContactCard(id: "anna", name: "Anna Beispiel", nameParts: ["Anna", "Beispiel"],
                               phones: [phone(.mobile, "Mobil", "0170 4")])
        let anja = ContactCard(id: "anja", name: "Anja Beispiel", nameParts: ["Anja", "Beispiel"],
                               phones: [phone(.mobile, "Mobil", "0170 3")])
        XCTAssertEqual(resolve(ContactRequest(person: "Anna Beispiel"), [anja, anna]),
                       .unique(CallTarget(name: "Anna Beispiel", label: "Mobil", number: number("01704")), .none))
    }

    func testEveryWordOfTheNameHasToFit() {
        XCTAssertEqual(resolve(ContactRequest(person: "Peter Gamma"), [peter("Alpha", "0170 1")]), .notFound,
                       "ein Peter mit anderem Nachnamen ist nicht der gesuchte")
    }

    func testNothingFitsMeansNotFound() {
        XCTAssertEqual(resolve(ContactRequest(person: "Zacharias"), [owner, mother]), .notFound)
        XCTAssertEqual(resolve(ContactRequest(person: "Zacharias"), []), .notFound)
    }

    func testAContactWithoutADialableNumberIsNamed() {
        let otto = ContactCard(id: "otto", name: "Otto Ohne", nameParts: ["Otto", "Ohne"],
                               phones: [phone(.other, "Anders", "*31#0170")])
        XCTAssertEqual(resolve(ContactRequest(person: "Otto"), [otto]), .noNumber("Otto Ohne"))
    }

    func testARelationWithoutItsOwnCardIsNamedAsWithoutNumber() {
        let lonely = ContactCard(id: "ich", name: "Gwen Nutzer", nameParts: ["Gwen", "Nutzer"],
                                 ties: [ContactTie(relation: .father, label: "Vater", name: "Karl Muster")])
        XCTAssertEqual(resolve(ContactRequest(person: "Papa", relation: .father), [lonely, mother]),
                       .noNumber("Karl Muster"))
    }

    func testTwoCardsWithTheSameNumberAreOnePerson() {
        let copy = ContactCard(id: "kopie", name: "Maria Muster", nameParts: ["Maria", "Muster", "Mama"],
                               phones: [phone(.mobile, "Handy", "+49 170 222 2222")])
        XCTAssertEqual(resolve(ContactRequest(person: "Mutter", relation: .mother), [owner, mother, copy]),
                       .unique(CallTarget(name: "Maria Muster", label: "Mobil", number: number("+491702222222")), .none))
    }

    func testTheParentRelationFindsBothParentsAndAsks() {
        let parents = ContactCard(id: "ich", name: "Gwen Nutzer", nameParts: ["Gwen", "Nutzer"],
                                  ties: [ContactTie(relation: .mother, label: "Mutter", name: "Maria Muster"),
                                         ContactTie(relation: .father, label: "Vater", name: "Karl Muster")])
        let father = ContactCard(id: "vater", name: "Karl Muster", nameParts: ["Karl", "Muster"],
                                 phones: [phone(.mobile, "Mobil", "0170 5")])
        XCTAssertEqual(resolve(ContactRequest(person: "Eltern", relation: .parent), [parents, mother, father]),
                       .ambiguous(["Maria Muster", "Karl Muster"]))
    }

    func testAMotherIsNeverTakenFromATieOfUnknownGender() {
        let owner = ContactCard(id: "ich", name: "Gwen Nutzer", nameParts: ["Gwen", "Nutzer"],
                                ties: [ContactTie(relation: .parent, label: "Elternteil", name: "Maria Muster")])
        XCTAssertEqual(resolve(ContactRequest(person: "Mama", relation: .mother), [owner, mother]), .notFound)
    }

    func testTheListStopsAtFiveNames() {
        let many = (1...7).map { peter("Nummer\($0)", "0170 \($0)") }
        guard case .ambiguous(let names) = resolve(ContactRequest(person: "Peter"), many) else {
            return XCTFail("mehrere Peter müssen nachgefragt werden")
        }
        XCTAssertEqual(names.count, ContactMatching.listedLimit)
    }

    func testTheSameNameTwiceIsToldApartByItsLabel() {
        let work = ContactCard(id: "zwei", name: "Maria Muster", nameParts: ["Maria", "Muster"],
                               phones: [phone(.work, "Arbeit", "089 7")])
        XCTAssertEqual(resolve(ContactRequest(person: "Maria Muster"), [mother, work]),
                       .ambiguous(["Maria Muster · Mobil", "Maria Muster · Arbeit"]))
    }

    func testUmlautsAndCaseDoNotMatter() {
        let mueller = ContactCard(id: "m", name: "Jörg Müller", nameParts: ["Jörg", "Müller"],
                                  phones: [phone(.mobile, "Mobil", "0170 6")])
        XCTAssertEqual(resolve(ContactRequest(person: "jorg muller"), [mueller]),
                       .unique(CallTarget(name: "Jörg Müller", label: "Mobil", number: number("01706")), .none))
    }

    func testABusinessIsFoundByItsOrganisationName() {
        let pizza = ContactCard(id: "p", name: "Pizzeria Roma", nameParts: ["Pizzeria Roma"],
                                phones: [phone(.main, "Haupt", "030 12345")])
        XCTAssertEqual(resolve(ContactRequest(person: "Pizzeria Roma"), [pizza]),
                       .unique(CallTarget(name: "Pizzeria Roma", label: "Haupt", number: number("03012345")), .none))
    }
}
