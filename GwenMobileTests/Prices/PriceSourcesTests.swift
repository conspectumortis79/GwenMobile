@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class PriceSourcesTests: GwenTestCase {
    func testTheQueryIsTheProductNameAndNothingElse() {
        XCTAssertEqual(PriceSources.queries(for: ["Jura ENA 4", "Kaffeevollautomat"]),
                       ["Jura ENA 4", "Kaffeevollautomat"])
        XCTAssertEqual(PriceSources.queries(for: ["Ekspres do kawy"]), ["Ekspres do kawy"])
        XCTAssertEqual(PriceSources.queries(for: ["Espressomaschine"]), ["Espressomaschine"],
                       "kein Land und keine Sprache hängt ein Wort an, die Query nimmt kein Land an")
    }

    func testQueryBuildingSkipsBlanksAndStopsAtTheTermBudget() {
        let terms = (1...6).map { "Produkt \($0)" }
        let queries = PriceSources.queries(for: terms)
        XCTAssertEqual(queries.count, PriceSources.maxTerms)
        XCTAssertEqual(queries.first, "Produkt 1")
        XCTAssertTrue(PriceSources.queries(for: ["   ", ""]).isEmpty)
    }

    func testMorePagesAreReadThanTheAnswerFinallyUses() {
        XCTAssertEqual(PriceSources.fetchWindow, 6)
        XCTAssertEqual(PriceSources.maxHits, 4)
        XCTAssertGreaterThan(PriceSources.fetchWindow, PriceSources.maxHits)
        let urls = (1...9).compactMap { URL(string: "https://shop\($0).test/a") }
        XCTAssertEqual(PriceSources.chosen(urls).count, PriceSources.fetchWindow)
    }

    func testPagesWithoutAPriceArePushedBackButNotInventedAway() {
        let priced = (1...6).map { index in
            Fixtures.hit("P\(index)", "https://p\(index).test/a", "p\(index).test", "539,00 €")
        }
        let empty = (1...3).map { index in
            Fixtures.hit("E\(index)", "https://e\(index).test/a", "e\(index).test", "nur Text")
        }
        let kept = PriceSources.kept(empty + priced)
        XCTAssertEqual(kept.map(\.domain), ["p1.test", "p2.test", "p3.test", "p4.test"])
        XCTAssertEqual(PriceSources.kept(empty).map(\.domain),
                       ["e1.test", "e2.test", "e3.test"],
                       "ohne Preis auf einer Seite entscheidet die Suche selbst, nicht das Ranking")
    }

    func testMergingSearchRoundsKeepsOnePagePerShopAndItsOrder() {
        let a = URL(string: "https://idealo.de/x")!
        let b = URL(string: "https://amazon.de/y")!
        XCTAssertEqual(WebPriceLookup.merged([[a, b], [b, a], []]), [a, b])
        let sameShopElsewhere = URL(string: "https://www.idealo.de/anderes-produkt")!
        XCTAssertEqual(WebPriceLookup.merged([[a, b], [sameShopElsewhere]]), [a, b],
                       "zwei Seiten desselben Ladens verbrennen einen der vier Slots")
        XCTAssertTrue(WebPriceLookup.merged([]).isEmpty)
    }
}
