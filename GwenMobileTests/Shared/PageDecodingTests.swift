@testable import GwenMobileFeatureCore
import Foundation
import XCTest

final class PageDecodingTests: XCTestCase {
    private func latin(_ text: String) throws -> Data {
        try XCTUnwrap(text.data(using: .isoLatin1))
    }

    func testValidUTF8IsReadAsItIsWhateverTheServerDeclares() {
        let data = Data("Größe und Maße".utf8)
        XCTAssertEqual(PageDecoding.text(of: data, declared: nil), "Größe und Maße")
        XCTAssertEqual(PageDecoding.text(of: data, declared: "iso-8859-1"), "Größe und Maße")
    }

    func testTheDeclaredCharsetOfTheResponseIsUsedForOtherBytes() throws {
        let data = try latin("Größe und Maße")
        XCTAssertEqual(PageDecoding.text(of: data, declared: "ISO-8859-1"), "Größe und Maße")
        XCTAssertEqual(PageDecoding.text(of: data, declared: " windows-1252 "), "Größe und Maße")
    }

    func testTheCharsetNamedInsideThePageIsUsedWhenTheResponseNamesNone() throws {
        let modern = try latin("<html><head><meta charset=\"iso-8859-1\"></head><body>Größe</body></html>")
        XCTAssertTrue(PageDecoding.text(of: modern, declared: nil).contains("Größe"))
        let classic = try latin("<meta http-equiv=\"Content-Type\" content=\"text/html; charset=windows-1252\">Maße")
        XCTAssertTrue(PageDecoding.text(of: classic, declared: nil).contains("Maße"))
        XCTAssertEqual(PageDecoding.sniffedName(in: modern), "iso-8859-1")
        XCTAssertEqual(PageDecoding.sniffedName(in: classic), "windows-1252")
        XCTAssertNil(PageDecoding.sniffedName(in: Data("<p>ohne Angabe</p>".utf8)))
    }

    func testBytesWithoutAUsableCharsetKeepTheLenientUTF8Reading() throws {
        let data = try latin("Größe")
        XCTAssertEqual(PageDecoding.text(of: data, declared: nil), String(decoding: data, as: UTF8.self))
        XCTAssertEqual(PageDecoding.text(of: data, declared: "kein-zeichensatz"),
                       String(decoding: data, as: UTF8.self))
        XCTAssertEqual(PageDecoding.text(of: data, declared: "utf-8"), String(decoding: data, as: UTF8.self))
    }

    func testCharsetNamesAreMappedOrRefused() {
        XCTAssertEqual(PageDecoding.encoding(named: "utf-8"), .utf8)
        XCTAssertEqual(PageDecoding.encoding(named: "ISO-8859-1"), .isoLatin1)
        XCTAssertEqual(PageDecoding.encoding(named: "windows-1252"), .windowsCP1252)
        XCTAssertNil(PageDecoding.encoding(named: nil))
        XCTAssertNil(PageDecoding.encoding(named: "  "))
        XCTAssertNil(PageDecoding.encoding(named: "kein-zeichensatz"))
    }

    func testOnlyTheStartOfThePageIsSearchedForACharset() throws {
        let padding = String(repeating: " ", count: PageDecoding.sniffedBytes)
        let late = try latin(padding + "<meta charset=\"iso-8859-1\">Größe")
        XCTAssertNil(PageDecoding.sniffedName(in: late))
    }

    func testDeclaredSevenBitEscapeEncodingWinsOverUTF8() throws {
        let japanese = "日本語"
        let encoded = try XCTUnwrap(japanese.data(using: .iso2022JP))
        XCTAssertTrue(encoded.contains(0x1B))
        XCTAssertEqual(PageDecoding.text(of: encoded, declared: "iso-2022-jp"), japanese)
    }
}
