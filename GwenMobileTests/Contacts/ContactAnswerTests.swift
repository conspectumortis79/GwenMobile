@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class ContactAnswerTests: GwenTestCase {
    func testTheWhoLineShowsTheLabelOnlyWhenThereIsOne() throws {
        let number = try XCTUnwrap(DialNumber("+49 30 1234567"))
        let labelled = CallTarget(name: "Maria", label: "Mobil", number: number)
        XCTAssertEqual(ContactAnswer.who(labelled), "Maria · Mobil")
        let plain = CallTarget(name: "Maria", label: "", number: number)
        XCTAssertEqual(ContactAnswer.who(plain), "Maria")
    }

    func testEveryRemarkKeepsItsOwnText() {
        XCTAssertNil(ContactAnswer.remark(.none))
        XCTAssertEqual(ContactAnswer.remark(.missing("Familie")),
                       L.fmt("contact_group_missing", "Familie"))
        XCTAssertEqual(ContactAnswer.remark(.outside("Familie")),
                       L.fmt("contact_group_outside", "Familie"))
        XCTAssertTrue(ContactAnswer.withRemark("Zeile", .outside("Familie")).hasPrefix("Zeile\n"))
        XCTAssertEqual(ContactAnswer.withRemark("Zeile", .none), "Zeile")
    }

    func testTheLookupFailureNamesItsReason() {
        XCTAssertEqual(ContactAnswer.lookupFailed(.denied), L.t("contact_denied"))
        XCTAssertEqual(ContactAnswer.lookupFailed(.unreadable("kaputt")), L.t("contact_unreadable"))
        XCTAssertEqual(ContactAnswer.lookupFailed(.resolved(.noNumber("Maria"), cards: 1)), "")
    }

    func testTheAskedLineFallsBackToTheRelation() {
        XCTAssertEqual(ContactAnswer.asked(ContactRequest(person: "Maria")), "Maria")
        XCTAssertEqual(ContactAnswer.asked(ContactRequest(person: "", relation: .mother)), "mother")
        XCTAssertEqual(ContactAnswer.asked(ContactRequest(person: "  ", relation: nil)), "")
    }
}
