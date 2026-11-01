@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class PricesGapCoverageTests: GwenTestCase {
    override func tearDown() {
        MockHTTP.uninstall()
        super.tearDown()
    }

    private func makeStore(_ prefix: String = "price-gap") -> PriceWatchStore {
        PriceWatchStore(paths: temporaryPaths(prefix))
    }

    private func watch(_ terms: [String] = ["PS5"], goal: Double = 400) -> PriceWatch {
        PriceWatch(terms: terms, goal: goal, currencyCode: "EUR", regionCode: "DE")
    }

    private func credentials() -> PriceWatchCredentials {
        PriceWatchCredentials(baseURL: "https://q.test/v1", key: "k", model: "m", thinking: .nothing)
    }

    func testTheFindingBlockCoversPriceAndEAN() {
        var finding = ProductFinding()
        finding.product = "PS5"
        finding.price = "499"
        finding.ean = "12345"
        XCTAssertTrue(finding.block.contains("499"))
        XCTAssertTrue(finding.block.contains("12345"))
    }

    func testTheRegionLabelsAndTraces() {
        let unknown = PriceRegion(code: nil, source: .open)
        XCTAssertNil(unknown.label)
        XCTAssertNil(unknown.promptLine)
        XCTAssertTrue(unknown.traceLine.contains("land=-"))
        let located = PriceRegion(code: "DE", source: .located)
        XCTAssertFalse(located.label?.isEmpty ?? true)
        XCTAssertTrue(located.traceLine.contains("woher=standort"))
        _ = PriceRegion.device()
        _ = PriceRegion.located("DE")
        _ = PriceRegion.named("Nirgendwo")
    }

    func testTheWatchRequestWordsAndDecoding() throws {
        let request = PriceWatchRequest(action: .create, terms: ["PS5"], goal: 400, country: "DE",
                                        intervalHours: 24, key: "ps5")
        XCTAssertTrue(request.stepWords.contains("24h"))
        XCTAssertTrue(request.stepWords.contains("#ps5"))
        XCTAssertTrue(request.stepWords.contains("PS5"))
        let decoded = try JSONDecoder().decode(PriceWatch.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded.terms, [])
        XCTAssertEqual(decoded.intervalHours, PriceWatch.defaultIntervalHours)
        XCTAssertEqual(decoded.product, "")
        XCTAssertFalse(decoded.paused)
        XCTAssertEqual(decoded.updatedAt, decoded.createdAt)
        XCTAssertEqual(decoded.goal, 0)
        var seenWatch = watch()
        seenWatch.lastPrice = 380
        XCTAssertEqual(PriceWatchRef(watch: seenWatch).bestText, Formatters.price(380, currency: "EUR"))
        seenWatch.lastShop = "Laden"
        XCTAssertTrue(PriceWatchRef(watch: seenWatch).bestText?.contains("Laden") ?? false)
        XCTAssertEqual(PriceWatch.cleanTerms((1...6).map { "Term\($0)" }).count, PriceWatch.maxTerms)
        let report = try XCTUnwrap(PriceWatchReport(arguments: #"{"price":"399,50","currency":"eur","shop":"Laden","source":1,"product":"PS5"}"#))
        XCTAssertEqual(report.price, 399.5)
        XCTAssertEqual(report.currency, "EUR")
        XCTAssertEqual(report.source, 1)
    }

    func testTheStoreCreateUpdateRecordAndCatalog() async throws {
        let store = makeStore()
        let invalidGoal = await store.create(terms: ["PS5"], goal: 0, intervalHours: 24,
                                             currencyCode: "EUR", regionCode: "DE")
        XCTAssertNil(invalidGoal)
        let invalidTerms = await store.create(terms: ["  "], goal: 10, intervalHours: 24,
                                              currencyCode: "EUR", regionCode: "DE")
        XCTAssertNil(invalidTerms)
        let madeOption = await store.create(terms: ["PS5"], goal: 400, intervalHours: 24,
                                            currencyCode: "EUR", regionCode: "DE")
        let made = try XCTUnwrap(madeOption)
        XCTAssertTrue(made.created)
        let updated = await store.update(id: made.watch.id, goal: 500, intervalHours: 12)
        XCTAssertEqual(updated?.goal, 500)
        XCTAssertEqual(updated?.intervalHours, 12)
        let unknownUpdate = await store.update(id: UUID(), goal: 1, intervalHours: 1)
        XCTAssertNil(unknownUpdate)
        await store.setPaused(id: UUID(), paused: true)
        await store.markNotified(id: UUID(), price: 1)
        await store.record(id: UUID(), offer: nil, fallbackCurrency: "EUR")
        await store.record(id: made.watch.id,
                           offer: PriceWatchOffer(price: 380, currency: "", shop: "", product: ""),
                           fallbackCurrency: "EUR")
        let recorded = await store.all().first
        XCTAssertEqual(recorded?.lastPrice, 380)
        XCTAssertEqual(recorded?.lastCurrency, "EUR")
        XCTAssertNil(recorded?.lastProduct)
        let catalog = await store.catalog()
        XCTAssertTrue(catalog.contains("PS5"))
    }

    func testThePriceAnswersCoverTheirStates() throws {
        let watch = watch()
        let offer = PriceWatchOffer(price: 350, currency: "EUR", shop: "MediaMarkt")
        let hit = PriceWatchCheckOutcome(watch: watch, offer: offer, failure: nil)
        XCTAssertTrue(PriceWatchAnswers.alarm(watch, offer: offer).contains("MediaMarkt"))
        XCTAssertTrue(PriceWatchAnswers.checked(hit).contains("350"))
        XCTAssertNotNil(PriceWatchAnswers.currentLine(hit))
        let cheapNoShop = PriceWatchOffer(price: 450)
        let waiting = PriceWatchCheckOutcome(watch: watch, offer: cheapNoShop, failure: nil)
        XCTAssertTrue(PriceWatchAnswers.checked(waiting).contains("450"))
        XCTAssertEqual(PriceWatchAnswers.currentLine(waiting),
                       L.fmt("price_watch_now", Formatters.price(450, currency: "EUR")))
        let failed = PriceWatchCheckOutcome(watch: watch, offer: nil, failure: "kaputt")
        XCTAssertTrue(PriceWatchAnswers.checkFailed(failed).contains("kaputt"))
        let silent = PriceWatchCheckOutcome(watch: watch, offer: nil, failure: nil)
        XCTAssertFalse(PriceWatchAnswers.checkFailed(silent).isEmpty)
        XCTAssertTrue(PriceWatchAnswers.checked(silent).contains(watch.product))
        XCTAssertTrue(PriceWatchAnswers.deleted(watch).contains("PS5"))
        XCTAssertEqual(PriceWatchAnswers.list([]), PriceWatchAnswers.empty())
        XCTAssertTrue(PriceWatchAnswers.list([watch]).contains("PS5"))
        var seen = watch
        seen.lastPrice = 380
        seen.lastCurrency = "EUR"
        seen.lastShop = "Laden"
        XCTAssertTrue(PriceWatchAnswers.listLine(seen).contains("Laden"))
        seen.lastShop = nil
        XCTAssertTrue(PriceWatchAnswers.listLine(seen).contains("380"))
        var checked = watch
        checked.lastCheckedAt = Date()
        XCTAssertFalse(PriceWatchAnswers.listLine(checked).isEmpty)
    }

    func testTheCheckerWithoutHitsAndWithoutAnOffer() async {
        let empty = LivePriceWatchChecker(lookup: TestPriceLookup(results: []))
        do {
            _ = try await empty.check(watch(), credentials: credentials())
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        let hit = WebHit(title: "PS5", url: "https://shop.test/ps5", domain: "shop.test",
                         text: String(repeating: "Angebot ", count: 60))
        MockHTTP.install { _ in
            (200, Data(#"{"choices":[{"message":{"content":"kein angebot"}}]}"#.utf8))
        }
        let checker = LivePriceWatchChecker(lookup: TestPriceLookup(results: [hit]))
        let offer = try? await checker.check(watch(), credentials: credentials())
        XCTAssertNil(offer)
    }
}

@MainActor
extension PricesGapCoverageTests {
    func testTheCheckerReportsARealOffer() async throws {
        let hit = WebHit(title: "PS5", url: "https://shop.test/ps5", domain: "shop.test",
                         text: String(repeating: "Angebot ", count: 60))
        MockHTTP.install { _ in
            (200, ToolCallPayload.single(LivePriceWatchChecker.reportTool,
                                         #"{"price":379,"source":"https://shop.test/ps5","product":"PS5"}"#))
        }
        defer { MockHTTP.uninstall() }
        let checker = LivePriceWatchChecker(lookup: TestPriceLookup(results: [hit]))
        let offer = try await checker.check(watch(), credentials: credentials())
        XCTAssertEqual(offer?.price, 379)
    }
}
