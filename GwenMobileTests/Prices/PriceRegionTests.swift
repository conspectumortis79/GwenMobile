@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class PriceRegionTests: GwenTestCase {
    func testACountryCodeIsAcceptedInAnyCase() {
        XCTAssertEqual(PriceRegion.named("de"), PriceRegion(code: "DE", source: .named))
        XCTAssertEqual(PriceRegion.named(" PL ")?.code, "PL")
        XCTAssertNil(PriceRegion.named("DD"))
        XCTAssertNil(PriceRegion.named(nil))
        XCTAssertNil(PriceRegion.named("  "))
    }

    func testACountryNameWorksInGermanAndInEnglish() {
        XCTAssertEqual(PriceRegion.named("Polen")?.code, "PL")
        XCTAssertEqual(PriceRegion.named("germany")?.code, "DE")
        XCTAssertEqual(PriceRegion.named("Schweiz")?.code, "CH")
        XCTAssertEqual(PriceRegion.named("United Kingdom")?.code, "GB")
    }

    func testCommonCountryShortNamesAreResolved() {
        XCTAssertEqual(PriceRegion.named("UK")?.code, "GB")
        XCTAssertEqual(PriceRegion.named("usa")?.code, "US")
        XCTAssertEqual(PriceRegion.named("England")?.code, "GB")
        XCTAssertEqual(PriceRegion.claimed("UK", in: "Was kostet das in UK?")?.code, "GB")
        XCTAssertEqual(PriceRegion.claimed("USA", in: "Was kostet das in den USA?")?.code, "US")
        XCTAssertEqual(PriceRegion.claimed("United Kingdom", in: "Was kostet das in UK?")?.code, "GB")
    }

    func testAWordThatIsNotACountryIsRefused() {
        XCTAssertNil(PriceRegion.named("idealo"))
        XCTAssertNil(PriceRegion.named("Kaffeevollautomat"))
        XCTAssertNil(PriceRegion.named("xy"))
    }

    func testTheDeviceRegionNeedsNoPermissionAndNamesItself() {
        let device = PriceRegion.device()
        XCTAssertEqual(device.source, .device)
        XCTAssertTrue(device.code == nil || device.code?.count == 2)
        XCTAssertTrue(PriceRegion(code: nil, source: .open).traceLine.hasPrefix("land=- woher=offen währung="))
        XCTAssertTrue(device.traceLine.contains("woher=gerät"), device.traceLine)
    }

    func testACountryIsOnlyBelievedWhenTheSentenceNamesIt() {
        XCTAssertEqual(PriceRegion.claimed("PL", in: "gibt es den Kaffeevollautomaten in Polen günstiger?")?.code,
                       "PL")
        XCTAssertEqual(PriceRegion.claimed("Polen", in: "gibt es den Kaffeevollautomaten in Polen günstiger?")?
                           .code, "PL",
                       "das Werkzeug darf das Wort des Nutzers direkt weitergeben")
        XCTAssertEqual(PriceRegion.claimed("polen", in: "in Polen gibt es das günstiger")?.code, "PL")
        XCTAssertEqual(PriceRegion.claimed("pl", in: "wo gibt es das in PL günstiger?")?.code, "PL")
        XCTAssertEqual(PriceRegion.claimed("US", in: "was kostet der in den Vereinigten Staaten?")?.code, "US")
        XCTAssertNil(PriceRegion.claimed("DE", in: "kannst du das irgendwo günstiger finden?"),
                     "ein Land, das der Nutzer nicht nennt, darf nicht behauptet werden")
        XCTAssertNil(PriceRegion.claimed("US", in: "was kostet das?"), "auch nicht durch Zufall im Wort")
        XCTAssertNil(PriceRegion.claimed(nil, in: "was kostet das?"))
    }

    func testTheCurrencyComesFromTheCountryAndNotFromATable() {
        XCTAssertEqual(PriceRegion.named("DE")?.currencyCode, "EUR")
        XCTAssertEqual(PriceRegion.named("CH")?.currencyCode, "CHF")
        XCTAssertEqual(PriceRegion.named("PL")?.currencyCode, "PLN")
        XCTAssertEqual(PriceRegion.named("CZ")?.currencyCode, "CZK")
        XCTAssertEqual(PriceRegion.named("GB")?.currencyCode, "GBP")
    }

    func testThePromptBlockNamesCountryAndCurrencyTogether() {
        let block = PriceRegion.named("Polen")?.promptLine ?? ""
        XCTAssertTrue(block.hasPrefix("## PRICE REGION\n"), block)
        XCTAssertTrue(block.contains("Polen"), block)
        XCTAssertTrue(block.contains("(PL)"), block)
        XCTAssertTrue(block.contains("PLN"), block)
        XCTAssertTrue(block.hasSuffix("\n\n"), block)
        XCTAssertNil(PriceRegion.unknown.promptLine)
    }

    func testALocatedCodeIsMarkedAsSuch() {
        XCTAssertEqual(PriceRegion.located("pl"), PriceRegion(code: "PL", source: .located))
        XCTAssertEqual(PriceRegion.located(nil), .unknown)
        XCTAssertEqual(PriceRegion.located("XX"), .unknown)
    }

    func testTheRegionTagUsesTheDocumentedDuckDuckGoCodes() {
        XCTAssertEqual(WebSearch.regionTag("DE", language: .de), "de-de")
        XCTAssertEqual(WebSearch.regionTag(" pl ", language: .de), "pl-pl")
        XCTAssertEqual(WebSearch.regionTag("GB", language: .en), "uk-en")
        XCTAssertEqual(WebSearch.regionTag("AT", language: .de), "at-de")
        XCTAssertEqual(WebSearch.regionTag("DK", language: .de), "dk-da")
        XCTAssertEqual(WebSearch.regionTag("SE", language: .en), "se-sv")
        XCTAssertEqual(WebSearch.regionTag("SI", language: .de), "sl-sl")
        XCTAssertNil(WebSearch.regionTag("deutschland"))
        XCTAssertNil(WebSearch.regionTag("D"))
        XCTAssertNil(WebSearch.regionTag("LU"))
    }

    func testTheRegionTagPicksTheVariantOfTheAppLanguage() {
        XCTAssertEqual(WebSearch.regionTag("CH", language: .de), "ch-de")
        XCTAssertEqual(WebSearch.regionTag("CH", language: .fr), "ch-fr")
        XCTAssertEqual(WebSearch.regionTag("CH", language: .en), "ch-de")
        XCTAssertEqual(WebSearch.regionTag("BE", language: .de), "be-fr")
        XCTAssertEqual(WebSearch.regionTag("CA", language: .fr), "ca-fr")
        XCTAssertEqual(WebSearch.regionTag("US", language: .en), "us-en")
        XCTAssertEqual(WebSearch.regionTag("US", language: .es), "us-es")
    }

    func testTheSearchRequestCarriesTheRegionAndRefusesAnEmptyQuery() throws {
        let withRegion = try WebSearch.searchRequest("Jura ENA 4 preis", region: "DE")
        XCTAssertTrue(withRegion.url?.absoluteString.contains("kl=de-de") == true,
                      withRegion.url?.absoluteString ?? "-")
        let without = try WebSearch.searchRequest("Jura ENA 4 preis")
        XCTAssertFalse(without.url?.absoluteString.contains("kl=") == true,
                       without.url?.absoluteString ?? "-")
        XCTAssertThrowsError(try WebSearch.searchRequest("   "))
    }

    func testNoShopOrSiteNameIsHardCodedAnywhereAnymore() {
        XCTAssertTrue(WebSearch.searchEndpoint.contains("duckduckgo"))
        XCTAssertEqual(WebSearch.ownRootDomain, "duckduckgo.com")
        XCTAssertTrue(WebSearch.isOwnResult(URL(string: "https://duckduckgo.com/xy")!))
        XCTAssertTrue(WebSearch.isOwnResult(URL(string: "https://html.duckduckgo.com/xy")!))
        XCTAssertFalse(WebSearch.isOwnResult(URL(string: "https://idealo.de/a")!),
                       "ein Laden darf nur über seinen Inhalt aussortiert werden, nicht über seinen Namen")
        XCTAssertFalse(WebSearch.isOwnResult(URL(string: "https://tagesschau.de/a")!))
    }
}
