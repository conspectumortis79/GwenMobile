@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class PriceComparatorTests: GwenTestCase {
    private var finding: ProductFinding {
        ProductFinding(product: "Jura ENA 4", brand: "Jura", price: "799 €", ean: "")
    }

    private var hits: [WebHit] {
        [Fixtures.hit("Idealo", "https://idealo.de/a", "idealo.de", "612,00 €"),
         Fixtures.hit("Notebooksbilliger", "https://notebooksbilliger.de/b", "notebooksbilliger.de", "649 €")]
    }

    func testThePriceContextKeepsThePictureFindingApartFromTheSources() throws {
        let history = [ChatMessage(role: .user, text: "Was kostet das Ding hier?"),
                       ChatMessage(role: .assistant, text: "Das ist ein Kaffeevollautomat.")]
        let context = PriceComparator.context(question: "gibt es den günstiger?", terms: ["Jura ENA 4"],
                                             finding: finding, region: .unknown, history: history, hits: hits)
        XCTAssertTrue(context.contains("## EARLIER CONVERSATION"), context)
        XCTAssertTrue(context.contains("## IMAGE FINDING"), context)
        XCTAssertTrue(context.contains("price shown on the picture: 799 €"), context)
        XCTAssertFalse(context.contains("## PRICE REGION"), "ohne Land wird keins behauptet")
        XCTAssertTrue(context.contains("## PRODUCT TERMS\nJura ENA 4"), context)
        XCTAssertTrue(context.contains("## SOURCE [1] Idealo — idealo.de"), context)
        XCTAssertTrue(context.hasSuffix("## QUESTION\ngibt es den günstiger?"), context)
        let findingAt = try XCTUnwrap(context.range(of: "## IMAGE FINDING")?.lowerBound)
        let sourceAt = try XCTUnwrap(context.range(of: "## SOURCE [1]")?.lowerBound)
        XCTAssertLessThan(findingAt, sourceAt, "der Bildbefund muss vor den Quellen stehen")
    }

    func testTheNamedCountryAndItsCurrencyTravelWithTheRequest() throws {
        let context = PriceComparator.context(question: "frage", terms: ["Ekspres do kawy"], finding: nil,
                                             region: PriceRegion.named("PL")!, history: [], hits: hits)
        XCTAssertTrue(context.contains("## PRICE REGION"), context)
        XCTAssertTrue(context.contains("PLN"), context)
        let findingAt = try XCTUnwrap(context.range(of: "## PRICE REGION")?.lowerBound)
        let sourceAt = try XCTUnwrap(context.range(of: "## SOURCE [1]")?.lowerBound)
        XCTAssertLessThan(findingAt, sourceAt, "das Land muss vor den Quellen stehen")
    }

    func testThePriceRequestCarriesNoPictureAndNoProtocolToken() throws {
        let request = try PriceComparator.makeAnswerRequest(baseURL: "https://api.test/v1", key: "k",
                                                            model: "m", question: "frage",
                                                            terms: ["Jura ENA 4"], finding: finding,
                                                            region: .unknown, history: [], hits: hits,
                                                            thinking: .nothing)
        let sent = try jsonMessages(of: request)
        let system = try XCTUnwrap(sent.first?["content"] as? String)
        XCTAssertFalse(system.contains(SearchMarker.token), system)
        XCTAssertTrue(system.contains("Answer ONLY from the web sources"), system)
        XCTAssertTrue(system.contains("never invent a price"), system)
        XCTAssertTrue(system.contains("PRICE REGION"), system)
        XCTAssertTrue(system.contains("currency the source itself prints"), system)
        let user = try XCTUnwrap(sent.last?["content"] as? String)
        XCTAssertTrue(user.contains("612,00 €"), user)
        XCTAssertEqual(sent.count, 2)
    }

    func testAComparisonWithoutAnyFindingStillNamesTheTermsItSearched() throws {
        let context = PriceComparator.context(question: "frage", terms: ["Sony WH-1000XM5"], finding: nil,
                                             region: .unknown, history: [], hits: hits)
        XCTAssertFalse(context.contains("## IMAGE FINDING"), context)
        XCTAssertTrue(context.contains("## PRODUCT TERMS\nSony WH-1000XM5"), context)
    }

    func testTheProductThePictureShowedIsSearchedEvenWhenTheRouterWasVague() {
        let terms = PriceComparator.searchedTerms(["das produkt", "Jura ENA 4"], finding: finding)
        XCTAssertEqual(terms, ["das produkt", "Jura ENA 4", "Jura"])
        XCTAssertEqual(PriceComparator.searchedTerms([], finding: finding), ["Jura ENA 4", "Jura"])
        XCTAssertEqual(PriceComparator.searchedTerms(["Sony WH-1000XM5"], finding: nil), ["Sony WH-1000XM5"])
    }

    func testNoOfferAnywhereIsReportedInsteadOfAGuess() async {
        let comparator = PriceComparator(lookup: StubPriceLookup())
        do {
            _ = try await comparator.compare(baseURL: "https://api.test/v1", key: "k", model: "m",
                                             question: "frage", terms: ["Jura"], finding: finding,
                                             region: .device(), history: [], thinking: .nothing)
            XCTFail("ohne Treffer darf keine Antwort entstehen")
        } catch let error as APIError {
            XCTAssertEqual(error.message, L.t("price_none_found"))
        } catch {
            XCTFail("anderer Fehler: \(error)")
        }
    }

    func testTheSearchFailureIsPassedThroughUnchanged() async {
        let comparator = PriceComparator(lookup: StubPriceLookup(failure: "HTTP 503"))
        do {
            _ = try await comparator.compare(baseURL: "https://api.test/v1", key: "k", model: "m",
                                             question: "frage", terms: ["Jura"], finding: nil,
                                             region: .unknown, history: [], thinking: .nothing)
            XCTFail("der Suchausfall hätte melde bleiben müssen")
        } catch let error as APIError {
            XCTAssertEqual(error.message, "HTTP 503")
        } catch {
            XCTFail("anderer Fehler: \(error)")
        }
    }

    func testASuccessfulSearchReturnsTheKeptPages() async throws {
        let page = "<html><head><title>Shop</title></head><body><p>"
            + String(repeating: "Ein langer Text mit Preis. ", count: 20)
            + "539,00 €</p></body></html>"
        MockHTTP.install { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("duckduckgo") {
                return (200, Data(#"<a class="result__a" href="https://shop.test/a">Shop</a>"#.utf8))
            }
            return (200, Data(page.utf8))
        }
        defer { MockHTTP.uninstall() }
        let lookup = WebPriceLookup(onStatus: { _ in })
        let hits = try await lookup.hits(for: ["PS5"], region: .device())
        XCTAssertFalse(hits.isEmpty)
    }

    func testAFailingSearchStillEndsTheCapsule() async {
        let texts = LockedValue(0)
        let ends = LockedValue(0)
        do {
            _ = try await WebPriceLookup(onStatus: { status in
                if status == nil { ends.mutate { $0 += 1 } } else { texts.mutate { $0 += 1 } }
            }).hits(for: [], region: .unknown)
            XCTFail("ohne Begriff darf keine Suche starten")
        } catch let error as APIError {
            XCTAssertEqual(error.message, L.t("web_no_results"))
        } catch {
            XCTFail("anderer Fehler: \(error)")
        }
        XCTAssertEqual(texts.current, 1, "zuerst meldet die Suche, dass sie sucht")
        XCTAssertEqual(ends.current, 1, "genau ein nil beendet die Kapsel — auch im Fehlerfall")
    }

    func testTheOfferRowIsHeadedAsOffersAndNotAsSources() {
        XCTAssertEqual(PriceComparator.headingKey, "price_head")
        XCTAssertEqual(L.t("price_head"), "Offers")
    }
}

@MainActor
struct StubPriceLookup: PriceLooking {
    var hits: [WebHit] = []
    var failure: String? = nil

    func hits(for terms: [String], region: PriceRegion) async throws -> [WebHit] {
        if let failure { throw APIError(message: failure) }
        return hits
    }
}
