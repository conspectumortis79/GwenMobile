@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class SearchShapeTests: GwenTestCase {
    private func hit(_ domain: String, _ text: String) -> WebHit {
        Fixtures.hit("Titel", "https://\(domain)/a", domain, text)
    }

    private let article = "Der Bundestag hat das Gesetz in dritter Lesung beschlossen. "
        + "Die Opposition stimmte geschlossen dagegen. "
        + "In Kraft treten soll es am kommenden Freitag. "

    func testARealArticlePassesOnItsShapeAlone() {
        XCTAssertEqual(SearchShape.sentences(in: article), 3)
        XCTAssertTrue(SearchShape.isSubstantial(hit("nachrichten.test", article)))
    }

    func testMenusAndWallsFailOnSentenceLengthNotOnTheirName() {
        let wall = "Cookies. Akzeptieren. Ablehnen. Impressum. Datenschutz. Login. Passwort. Suche. Menü."
        XCTAssertEqual(SearchShape.sentences(in: wall), 9, "Kurzfragmente zählen als Sätze")
        XCTAssertFalse(SearchShape.isSubstantial(hit("shop.test", wall)),
                       "9 Sätze auf 90 Zeichen sind keine Prosa")
        XCTAssertFalse(SearchShape.isSubstantial(hit("video.test", "")))
        XCTAssertFalse(SearchShape.isSubstantial(hit("price.test", "Nur ein Preis: 799,00 €")))
    }

    func testTheSameTextJudgesTheSameWhateverTheDomainIs() {
        XCTAssertTrue(SearchShape.isSubstantial(hit("reddit.test", article)))
        XCTAssertTrue(SearchShape.isSubstantial(hit("tagesschau.test", article)))
        XCTAssertFalse(SearchShape.isSubstantial(hit("tagesschau.test", "Kurz. Kurz. Kurz.")))
        XCTAssertFalse(SearchShape.isSubstantial(hit("unbekannt.test", "Kurz. Kurz. Kurz.")))
    }

    func testNothingIsThrownAwayWhenNoPageLooksLikeProse() {
        let weak = [hit("a.test", "Nur ein Wort."), hit("b.test", "Auch nur eins.")]
        XCTAssertEqual(SearchShape.substantial(weak).map(\.domain), ["a.test", "b.test"],
                       "ohne jede Prosa-Seite bleibt die alte Auswahl — sonst gäbe es gar keine Quelle")
        XCTAssertTrue(SearchShape.substantial([]).isEmpty)
    }

    func testTheSearchEngineOrderSurvivesTheShapeFilter() {
        let first = hit("first.test", article)
        let second = hit("second.test", "Die Zahlen stiegen im dritten Quartal deutlich. "
                         + "Ein Sprecher bestätigte den Trend auf Anfrage. "
                         + "Für das nächste Jahr wird vorsichtig optimiert.")
        let junk = hit("junk.test", "Kauf. Warenkorb. Zahlung. Versand.")
        XCTAssertEqual(SearchShape.substantial([first, second, junk]).map(\.domain),
                       ["first.test", "second.test"])
    }
}
