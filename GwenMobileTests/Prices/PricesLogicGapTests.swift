@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class PricesLogicGapTests: GwenTestCase {
    private func hit(_ title: String, _ url: String) -> WebHit {
        Fixtures.hit(title, url, "shop.test", String(repeating: "Guter Preis 199 Euro. ", count: 30))
    }

    func testTheComparatorBuildsAnAnswer() async throws {
        MockHTTP.install { _ in (200, MockHTTP.completion("Der Preis liegt bei 199 Euro. [1]")) }
        let lookup = TestPriceLookup(hits: [hit("Erster Laden", "https://shop.test/a"),
                                           hit("Zweiter Laden", "https://shop.test/b")])
        let comparator = PriceComparator(lookup: lookup)
        let comparison = try await comparator.compare(baseURL: "https://q.test/v1", key: "k",
                                                      model: "m", question: "Was kostet es?",
                                                      terms: ["MacBook"], finding: nil,
                                                      region: PriceRegion(code: "DE", source: .named),
                                                      history: [], thinking: .nothing)
        XCTAssertFalse(comparison.text.isEmpty)
        XCTAssertFalse(comparison.sources.isEmpty)
        XCTAssertEqual(comparison.headingKey, PriceComparator.headingKey)
    }

    func testTheComparatorErrors() async {
        let failing = PriceComparator(lookup: TestPriceLookup(fails: true))
        do {
            _ = try await failing.compare(baseURL: "https://q.test/v1", key: "k", model: "m",
                                          question: "Q", terms: ["x"], finding: nil,
                                          region: PriceRegion(code: "DE", source: .named),
                                          history: [], thinking: .nothing)
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        let empty = PriceComparator(lookup: TestPriceLookup(hits: []))
        do {
            _ = try await empty.compare(baseURL: "https://q.test/v1", key: "k", model: "m",
                                        question: "Q", terms: ["x"], finding: nil,
                                        region: PriceRegion(code: "DE", source: .named),
                                        history: [], thinking: .nothing)
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    func testTheMergedLookupURLs() {
        let one = URL(string: "https://a.test/seite")!
        let two = URL(string: "https://a.test/zwei")!
        let three = URL(string: "https://b.test/drei")!
        let merged = WebPriceLookup.merged([[one, two], [three]])
        XCTAssertEqual(merged.count, 2)
    }

    func testTheWatchCatalogNamesTheOffer() async {
        let store = PriceWatchStore(paths: temporaryPaths("price-catalog"))
        let created = await store.create(terms: ["PS5"], goal: 400, intervalHours: 24,
                                         currencyCode: "EUR", regionCode: "DE")
        if let id = created?.watch.id {
            await store.record(id: id, offer: PriceWatchOffer(price: 380, currency: "EUR",
                                                              shop: "Laden", product: "PS5 Slim"),
                               fallbackCurrency: "EUR")
        }
        let catalog = await store.catalog()
        XCTAssertTrue(catalog.contains("PS5"), catalog)
        XCTAssertTrue(catalog.contains("offer"), catalog)
    }
}
