@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class PhoneLinksTests: XCTestCase {
    private func found(_ text: String) -> [String] {
        PhoneLinks.matches(in: text).map { String(text[$0.range]) }
    }

    func testEveryUsualWayOfWritingANumberBecomesALink() {
        XCTAssertEqual(found("Ruf 0170 1234567 an."), ["0170 1234567"])
        XCTAssertEqual(found("Erreichbar unter +49 30 12345678."), ["+49 30 12345678"])
        XCTAssertEqual(found("0170/2222222"), ["0170/2222222"])
        XCTAssertEqual(found("(030) 123456"), ["(030) 123456"])
        XCTAssertEqual(found("dann (030 123456) anrufen"), ["030 123456"])
        XCTAssertEqual(found("0049 170 2222222"), ["0049 170 2222222"])
        XCTAssertEqual(found("Tel.: 0170-222-2222"), ["0170-222-2222"])
        XCTAssertEqual(found("Mobil +43 1 234 5678"), ["+43 1 234 5678"])
        XCTAssertEqual(found("Zentrale 030 123.4567"), ["030 123.4567"])
    }

    func testTheLinkCarriesOnlyWhatCanBeDialled() {
        let text = "Ruf +49 (170) 222-2222 an"
        XCTAssertEqual(PhoneLinks.matches(in: text).first?.number.digits, "+491702222222")
    }

    func testTheTrunkZeroAfterACountryCodeNeverReachesTheDialTarget() {
        let text = "Ruf +49 (0) 30 12345678 an."
        XCTAssertEqual(found(text), ["+49 (0) 30 12345678"])
        XCTAssertEqual(PhoneLinks.matches(in: text).first?.number.digits, "+493012345678")
        XCTAssertEqual(PhoneLinks.matches(in: "+49 (030) 123456").first?.number.digits, "+4930123456")
        XCTAssertEqual(PhoneLinks.matches(in: "+49 (0 30) 123456").first?.number.digits, "+4930123456")
        XCTAssertEqual(PhoneLinks.matches(in: "(030) 123456").first?.number.digits, "030123456")
    }

    func testDatesPricesTimesAndVersionsStayPlainText() {
        XCTAssertEqual(found("Am 01.01.2024 ist der Termin."), [])
        XCTAssertEqual(found("Der Termin am 24.12. bleibt."), [])
        XCTAssertEqual(found("Es kostet 0.99 Euro."), [])
        XCTAssertEqual(found("Preis 1.299,00 Euro."), [])
        XCTAssertEqual(found("Um 14:30 Uhr."), [])
        XCTAssertEqual(found("Version 2.0.1 ist da."), [])
    }

    func testPostalCodesRoomsAndShortCodesStayPlainText() {
        XCTAssertEqual(found("Die PLZ ist 01067."), [])
        XCTAssertEqual(found("Zimmer 101"), [])
        XCTAssertEqual(found("Ruf 112 an."), [])
    }

    func testLettersAndOtherCodesAreNoPhoneNumber() {
        XCTAssertEqual(found("0800-FLOWERS"), [])
        XCTAssertEqual(found("Artikelnummer 123456789"), [])
        XCTAssertEqual(found("x030 123456"), [])
        XCTAssertEqual(found("030 1234567x"), [])
        XCTAssertEqual(found("Steuernummer 12/345/67890"), [])
        XCTAssertEqual(found("Seite 100-200"), [])
    }

    func testSeveralNumbersInOneAnswerBecomeSeveralLinks() {
        XCTAssertEqual(found("Zentrale 030 123456, Durchwahl 0170 2222222."),
                       ["030 123456", "0170 2222222"])
    }

    func testTheBoundariesNeverCarryPunctuationIntoTheLink() {
        XCTAssertEqual(found("**0170 1234567**, dann (030 123456)."), ["0170 1234567", "030 123456"])
    }

    func testEveryLinkPointsAtItsOwnNumber() {
        let text = "Erst 030 123456, dann 0170 2222222."
        let links = PhoneLinks.matches(in: text)
        XCTAssertEqual(links.map(\.number.digits), ["030123456", "01702222222"])
        XCTAssertEqual(links.map { String(text[$0.range]) }, ["030 123456", "0170 2222222"])
    }
}
