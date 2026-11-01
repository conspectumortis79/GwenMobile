@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class ProductFindingTests: GwenTestCase {
    func testTheWholeReportedProductIsDecoded() throws {
        let arguments = #"""
        {"product":"Sony WH-1000XM5 Kopfhörer","brand":"Sony","price":"349 €","ean":"4548736129657"}
        """#
        let finding = try XCTUnwrap(ProductFinding(arguments: arguments))
        XCTAssertEqual(finding.product, "Sony WH-1000XM5 Kopfhörer")
        XCTAssertEqual(finding.brand, "Sony")
        XCTAssertEqual(finding.price, "349 €")
        XCTAssertEqual(finding.ean, "4548736129657")
        XCTAssertTrue(finding.isUsable)
    }

    func testOnlyTheValuesTheToolDeclaresAreRead() throws {
        let finding = try XCTUnwrap(ProductFinding(
            arguments: #"{"product":"Jura ENA 4","preis":"799 €","hersteller":"Jura","name":"ENA 4"}"#))
        XCTAssertEqual(finding.product, "Jura ENA 4")
        XCTAssertTrue(finding.brand.isEmpty)
        XCTAssertTrue(finding.price.isEmpty)
    }

    func testAnEmptyProductIsNeverAClue() {
        XCTAssertNil(ProductFinding(arguments: #"{"product":"","brand":"Sony","price":"349 €"}"#))
        XCTAssertNil(ProductFinding(arguments: #"{"produkt":"Sony"}"#))
        XCTAssertNil(ProductFinding(arguments: "{}"))
        XCTAssertNil(ProductFinding(arguments: ""))
        XCTAssertNil(ProductFinding(arguments: "{product"))
        XCTAssertNil(ProductFinding(arguments: #"[{"product":"Jura ENA 4"}]"#))
    }

    func testOverlongValuesAreClippedToTheirBudget() throws {
        let arguments = "{\"product\":\"\(String(repeating: "a", count: 300))\","
            + "\"brand\":\"\(String(repeating: "b", count: 100))\","
            + "\"price\":\"\(String(repeating: "c", count: 100))\","
            + "\"ean\":\"\(String(repeating: "1", count: 100))\"}"
        let finding = try XCTUnwrap(ProductFinding(arguments: arguments))
        XCTAssertEqual(finding.product.count, ProductFinding.maxProductChars)
        XCTAssertEqual(finding.brand.count, ProductFinding.maxBrandChars)
        XCTAssertEqual(finding.price.count, ProductFinding.maxPriceChars)
        XCTAssertEqual(finding.ean.count, ProductFinding.maxCodeChars)
    }

    func testLineBreaksAndDoubleSpacesInsideAValueCollapse() throws {
        let finding = try XCTUnwrap(ProductFinding(arguments: #"{"product":"  Sony  \n  WH-1000XM5  "}"#))
        XCTAssertEqual(finding.product, "Sony WH-1000XM5")
    }

    func testAQuotedValueLosesItsQuotes() throws {
        let finding = try XCTUnwrap(ProductFinding(arguments: #"{"product":"\"Jura ENA 4\""}"#))
        XCTAssertEqual(finding.product, "Jura ENA 4")
    }

    func testTheBlockNamesEveryValueAndEndsBeforeTheSources() {
        let finding = ProductFinding(product: "Sony WH-1000XM5", brand: "Sony", price: "349 €", ean: "")
        let block = finding.block
        XCTAssertTrue(block.hasPrefix("## IMAGE FINDING\n"), block)
        XCTAssertTrue(block.contains("product: Sony WH-1000XM5"), block)
        XCTAssertTrue(block.contains("brand: Sony"), block)
        XCTAssertTrue(block.contains("price shown on the picture: 349 €"), block)
        XCTAssertFalse(block.contains("ean:"), block)
        XCTAssertTrue(block.hasSuffix("\n\n"), block)
    }

    func testAnEmptyFindingContributesNoBlock() {
        XCTAssertEqual(ProductFinding().block, "")
        XCTAssertFalse(ProductFinding().isUsable)
        XCTAssertTrue(ProductFinding().identityTerms.isEmpty)
    }

    func testIdentityTermsLeadWithTheMostSpecificNamingAndNeverRepeat() {
        let finding = ProductFinding(product: "WH-1000XM5", brand: "Sony", price: "", ean: "")
        XCTAssertEqual(finding.identityTerms, ["Sony WH-1000XM5", "WH-1000XM5", "Sony"])
        let alone = ProductFinding(product: "Kaffee", brand: "Kaffee", price: "", ean: "")
        XCTAssertEqual(alone.identityTerms, ["Kaffee"])
        let named = ProductFinding(product: "Sony WH-1000XM5", brand: "Sony", price: "", ean: "")
        XCTAssertEqual(named.identityTerms, ["Sony WH-1000XM5", "Sony"])
    }

    func testTheTraceLineCarriesEverythingOrADash() {
        XCTAssertEqual(ProductFinding(product: "A", brand: "", price: "2 €", ean: "").traceLine, "A · 2 €")
        XCTAssertEqual(ProductFinding().traceLine, "-")
    }
}
