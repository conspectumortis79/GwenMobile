@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class PriceEvidenceTests: GwenTestCase {
    func testEveryWrittenPriceIsRecognised() {
        let priced = [
            "1.299,00 €", "€ 99", "99 EUR", "Preis: 5.990 zł", "5kr", "£1,299.00", "$45",
            "Versand 4,95 €", "CHF 799.-", "Euro 1.299,00", "ab 299,00 € inkl. MwSt.",
            "цена 12 990 руб", "грн 1 299", "Kč 4 990",
        ]
        for text in priced {
            XCTAssertTrue(PriceEvidence.hasPrice(text), "\(text) ist ein Preis")
        }
    }

    func testNumbersWithoutACurrencyStayNumbers() {
        for text in ["1200 Krone", "Ich habe keinen Preis gefunden", "2024 war das Jahr",
                     "Krise im Handel", "Modell 2024, 15.000 km", "EURopäische Qualität",
                     "Lagerbestand 12", ""] {
            XCTAssertFalse(PriceEvidence.hasPrice(text), "\(text) ist kein Preis")
        }
    }

    func testAPriceWrittenWithEntitiesKeepsItsCurrencyInThePageText() {
        let page = "<div class=\"price\">19,99&nbsp;&euro;</div><span>&#8364; 1.299</span>"
        let text = HTMLText.plain(page, hiding: HTMLText.pageNoiseBlocks)
        XCTAssertEqual(PriceEvidence.mentions(in: text), 2)
    }

    func testSeveralOffersInOnePageAreCounted() {
        XCTAssertEqual(PriceEvidence.mentions(in: "£1,299.00 und $45 Versand"), 2)
        XCTAssertEqual(PriceEvidence.mentions(in: "kein Preis genannt"), 0)
    }

    func testTheDetectorReallyRunsAndNeverSilentlyDisappears() {
        XCTAssertGreaterThan(PriceEvidence.mentions(in: "12,90 €"), 0,
                             "ein kaputtes Muster zählt überall null und würde jede Preissuche leer machen")
    }

    func testRankedLeadsWithPagesThatShowAPriceAndKeepsTheRestInOrder() {
        let hits = [Fixtures.hit("Forum", "https://a.test/1", "a.test", "Viel Text ohne Zahl"),
                    Fixtures.hit("Shop", "https://b.test/2", "b.test", "Gerät 539,00 € inkl. Versand"),
                    Fixtures.hit("Blog", "https://c.test/3", "c.test", "Bericht über Kaffeevollautomaten"),
                    Fixtures.hit("Idealo", "https://d.test/4", "d.test", "Preisvergleich: 612 EUR")]
        XCTAssertEqual(PriceEvidence.ranked(hits).map(\.domain), ["b.test", "d.test", "a.test", "c.test"])
        XCTAssertEqual(PriceEvidence.withPrice(hits).count, 2)
    }

    func testRankingAnEmptyListStaysEmpty() {
        XCTAssertTrue(PriceEvidence.ranked([]).isEmpty)
        XCTAssertTrue(PriceEvidence.withPrice([]).isEmpty)
    }
}
