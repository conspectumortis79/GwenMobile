@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import UserNotifications
import XCTest
import GwenMobileKit

@MainActor
private final class StubPriceWatchChecker: PriceWatchChecking {
    var offers: [PriceWatchOffer?] = []
    var failure: Error?
    private(set) var checks: [PriceWatch] = []

    func check(_ watch: PriceWatch, credentials: PriceWatchCredentials) async throws -> PriceWatchOffer? {
        checks.append(watch)
        if let failure { throw failure }
        return offers.isEmpty ? nil : offers.removeFirst()
    }
}

@MainActor
private final class RecordingPriceWatchNotifier: PriceWatchNotifying {
    private(set) var prepared = 0
    private(set) var notified: [PriceWatch] = []
    var delivers = true

    func prepare() { prepared += 1 }

    func notify(_ watch: PriceWatch, offer: PriceWatchOffer) async -> Bool {
        guard delivers else { return false }
        notified.append(watch)
        return true
    }
}

@MainActor
final class PriceWatchFlowTests: GwenTestCase {
    private func makeStore() -> (PriceWatchStore, StoragePaths) {
        let paths = temporaryPaths("gwen-watch")
        return (PriceWatchStore(paths: paths), paths)
    }

    private func credentials() -> PriceWatchCredentials {
        PriceWatchCredentials(baseURL: "https://api.test/v1", key: "k", model: "m", thinking: .nothing)
    }

    private func offer(_ price: Double, shop: String = "MediaMarkt") -> PriceWatchOffer {
        PriceWatchOffer(price: price, currency: "EUR", shop: shop, url: "https://mediamarkt.de/x")
    }

    private func createRequest(terms: [String] = ["PlayStation 5", "PS5"], goal: Double = 400)
        -> PriceWatchRequest {
        PriceWatchRequest(action: .create, terms: terms, goal: goal)
    }

    func testSmokeTheLocalNotifierUsesTheSystemDefaults() async {
        _ = await LocalPriceWatchNotifier.delivery.authorizationStatus()
        let request = UNNotificationRequest(identifier: "gwen.test.\(UUID().uuidString)",
                                            content: UNMutableNotificationContent(), trigger: nil)
        _ = try? await LocalPriceWatchNotifier.delivery.deliver(request)
    }

    func testTheLocalNotifierHandlesDeniedDeliveredAndFailedNotifications() async {
        let originalStatus = LocalPriceWatchNotifier.delivery.authorizationStatus
        let originalDeliver = LocalPriceWatchNotifier.delivery.deliverOverride
        defer {
            LocalPriceWatchNotifier.delivery.authorizationStatus = originalStatus
            LocalPriceWatchNotifier.delivery.deliverOverride = originalDeliver
        }
        let watch = PriceWatch(terms: ["PlayStation 5"], goal: 400, currencyCode: "EUR")
        let offer = offer(350)
        LocalPriceWatchNotifier.delivery.authorizationStatus = { .denied }
        let denied = await LocalPriceWatchNotifier().notify(watch, offer: offer)
        XCTAssertFalse(denied)
        LocalPriceWatchNotifier.delivery.authorizationStatus = { .authorized }
        LocalPriceWatchNotifier.delivery.deliverOverride = { _ in }
        let delivered = await LocalPriceWatchNotifier().notify(watch, offer: offer)
        XCTAssertTrue(delivered)
        LocalPriceWatchNotifier.delivery.deliverOverride = { _ in throw APIError(message: "kaputt") }
        let failed = await LocalPriceWatchNotifier().notify(watch, offer: offer)
        XCTAssertFalse(failed)
        LocalPriceWatchNotifier.delivery.authorizationStatus = { .provisional }
        LocalPriceWatchNotifier.delivery.deliverOverride = { _ in }
        let provisional = await LocalPriceWatchNotifier().notify(watch, offer: offer)
        XCTAssertTrue(provisional)
    }

    func testTheMissingWatchOutcomesAndRestore() async {
        let (store, _) = makeStore()
        let runner = PriceWatchFlowRunner(store: store, checker: StubPriceWatchChecker(),
                                          credentials: credentials(),
                                          notifier: RecordingPriceWatchNotifier())
        for action in [PriceWatchAction.update, .delete, .check] {
            let request = PriceWatchRequest(action: action, terms: ["GibtEsNicht"], goal: 100)
            let outcome = await runner.run(request, question: "frage")
            XCTAssertFalse(outcome.text.isEmpty)
        }
        let created = await runner.run(PriceWatchRequest(action: .create, terms: [], goal: 100),
                                       question: "frage")
        XCTAssertFalse(created.text.isEmpty)
        let desk = PriceWatchDesk()
        desk.stand(in: StubPriceWatchChecker(), notifier: RecordingPriceWatchNotifier())
        _ = desk.checker { _ in }
        _ = desk.notifier()
        desk.restore()
        _ = desk.notifier()
    }

    func testAFailedNotificationDoesNotMarkThePriceAsDelivered() async {
        let (store, _) = makeStore()
        let checker = StubPriceWatchChecker()
        checker.offers = [offer(350)]
        let notifier = RecordingPriceWatchNotifier()
        notifier.delivers = false
        let runner = PriceWatchFlowRunner(store: store, checker: checker, credentials: credentials(),
                                          notifier: notifier)
        _ = await runner.run(createRequest(), question: "unter 400 Euro")
        let watches = await store.all()
        XCTAssertNil(watches.first?.notifiedPrice)
    }

    func testCreateStoresTheWatchRunsOneCheckAndAnswersWithACard() async {
        let (store, _) = makeStore()
        let checker = StubPriceWatchChecker()
        checker.offers = [offer(429)]
        let notifier = RecordingPriceWatchNotifier()
        let runner = PriceWatchFlowRunner(store: store, checker: checker, credentials: credentials(),
                                          notifier: notifier)
        let outcome = await runner.run(createRequest(), question: "Sag mir Bescheid, wenn die PS5 unter 400 € fällt")
        XCTAssertEqual(checker.checks.count, 1)
        XCTAssertEqual(notifier.prepared, 1)
        XCTAssertTrue(notifier.notified.isEmpty, "429 liegt über dem Ziel")
        let text = outcome.text
        XCTAssertTrue(text.contains("Price watch set up"), text)
        XCTAssertTrue(text.contains("429"), text)
        XCTAssertTrue(text.contains("MediaMarkt"), text)
        XCTAssertEqual(outcome.ref?.product, "PlayStation 5")
        XCTAssertEqual(outcome.ref?.goal, 400)
        XCTAssertEqual(outcome.ref?.bestPrice, 429)
        XCTAssertEqual(outcome.ref?.status, .waiting)
        let watches = await store.all()
        XCTAssertEqual(watches.count, 1)
        XCTAssertEqual(watches.first?.lastCheckedAt != nil, true)
    }

    func testTheSameProductIsUpdatedInsteadOfStoredTwice() async {
        let (store, _) = makeStore()
        let checker = StubPriceWatchChecker()
        let runner = PriceWatchFlowRunner(store: store, checker: checker, credentials: credentials(),
                                          notifier: RecordingPriceWatchNotifier())
        _ = await runner.run(createRequest(goal: 400), question: "frage")
        let second = await runner.run(createRequest(terms: ["PlayStation 5"], goal: 350), question: "frage")
        XCTAssertTrue(second.text.contains("changed"), second.text)
        let watches = await store.all()
        XCTAssertEqual(watches.count, 1)
        XCTAssertEqual(watches.first?.goal, 350)
    }

    func testAHitIsAnnouncedAndNotRepeatedForTheSamePrice() async {
        let (store, _) = makeStore()
        let checker = StubPriceWatchChecker()
        checker.offers = [offer(379), offer(379), offer(359)]
        let notifier = RecordingPriceWatchNotifier()
        let runner = PriceWatchFlowRunner(store: store, checker: checker, credentials: credentials(),
                                          notifier: notifier)
        let first = await runner.run(createRequest(goal: 400), question: "frage")
        XCTAssertTrue(first.text.contains("Price alarm"), first.text)
        XCTAssertEqual(notifier.notified.count, 1)
        _ = await runner.run(PriceWatchRequest(action: .check, terms: ["PlayStation 5"]), question: "frage")
        XCTAssertEqual(notifier.notified.count, 1, "derselbe Preis darf nicht erneut melden")
        _ = await runner.run(PriceWatchRequest(action: .check, terms: ["PlayStation 5"]), question: "frage")
        XCTAssertEqual(notifier.notified.count, 2, "ein tieferer Preis meldet wieder")
        XCTAssertEqual(first.ref?.status, .hit)
    }

    func testAFailedCheckKeepsTheWatchAndSaysWhy() async {
        let (store, _) = makeStore()
        let checker = StubPriceWatchChecker()
        checker.failure = APIError(message: "HTTP 503")
        let runner = PriceWatchFlowRunner(store: store, checker: checker, credentials: credentials(),
                                          notifier: RecordingPriceWatchNotifier())
        let outcome = await runner.run(createRequest(), question: "frage")
        XCTAssertTrue(outcome.text.contains("did not work"), outcome.text)
        XCTAssertTrue(outcome.text.contains("HTTP 503"), outcome.text)
        let watches = await store.all()
        XCTAssertEqual(watches.count, 1)
        XCTAssertNotNil(watches.first?.lastCheckedAt)
        let due = await store.due(now: Date())
        XCTAssertTrue(due.isEmpty, "eine fehlgeschlagene Prüfung zählt als Prüfung")
    }

    func testDeleteListAndMissingWatches() async {
        let (store, _) = makeStore()
        let checker = StubPriceWatchChecker()
        let runner = PriceWatchFlowRunner(store: store, checker: checker, credentials: credentials(),
                                          notifier: RecordingPriceWatchNotifier())
        _ = await runner.run(createRequest(goal: 400), question: "frage")
        _ = await runner.run(PriceWatchRequest(action: .create, terms: ["Kopfhörer Aura X"], goal: 199),
                             question: "frage")
        let list = await runner.run(PriceWatchRequest(action: .list), question: "Welche Preis-Wecker habe ich?")
        XCTAssertTrue(list.text.contains("PlayStation 5"), list.text)
        XCTAssertTrue(list.text.contains("Kopfhörer Aura X"), list.text)
        XCTAssertTrue(list.text.contains("target"), list.text)
        let deleted = await runner.run(PriceWatchRequest(action: .delete, terms: ["PlayStation 5"]),
                                       question: "frage")
        XCTAssertTrue(deleted.text.contains("deleted"), deleted.text)
        let rest = await store.all()
        XCTAssertEqual(rest.map(\.product), ["Kopfhörer Aura X"])
        let missing = await runner.run(PriceWatchRequest(action: .delete, terms: ["Notebook"]), question: "frage")
        XCTAssertTrue(missing.text.contains("no price watch"), missing.text)
    }

    func testDueChecksWaitForTheIntervalAndStopWhilePaused() async {
        let (store, _) = makeStore()
        let start = Date()
        let made = await store.create(terms: ["PlayStation 5"], goal: 400, intervalHours: nil,
                                      currencyCode: "EUR", regionCode: "DE", now: start)
        let watch = try? XCTUnwrap(made?.watch)
        XCTAssertEqual(watch?.intervalHours, PriceWatch.defaultIntervalHours)
        let before = await store.due(now: start.addingTimeInterval(23 * 3600))
        XCTAssertTrue(before.isEmpty)
        let after = await store.due(now: start.addingTimeInterval(25 * 3600))
        XCTAssertEqual(after.count, 1)
        await store.setPaused(id: watch?.id ?? UUID(), paused: true)
        let paused = await store.due(now: start.addingTimeInterval(25 * 3600))
        XCTAssertTrue(paused.isEmpty)
        let next = await store.nextDueDate()
        XCTAssertNil(next)
    }

    func testCheckDueReturnsOnlyHitsAndRecordsEveryWatch() async {
        let (store, _) = makeStore()
        _ = await store.create(terms: ["PlayStation 5"], goal: 400, intervalHours: 6,
                               currencyCode: "EUR", regionCode: "DE")
        _ = await store.create(terms: ["Kopfhörer Aura X"], goal: 100, intervalHours: 6,
                               currencyCode: "EUR", regionCode: "DE")
        let checker = StubPriceWatchChecker()
        checker.offers = [offer(379), offer(249)]
        let notifier = RecordingPriceWatchNotifier()
        let runner = PriceWatchFlowRunner(store: store, checker: checker, credentials: credentials(),
                                          notifier: notifier)
        let hits = await runner.checkDue(now: Date().addingTimeInterval(7 * 3600))
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.watch.product, "PlayStation 5")
        XCTAssertEqual(notifier.notified.count, 1)
        XCTAssertEqual(checker.checks.count, 2)
    }

    func testTheCatalogCarriesTheKeyProductGoalAndStatus() async {
        let (store, _) = makeStore()
        let made = await store.create(terms: ["PlayStation 5"], goal: 400, intervalHours: 24,
                                      currencyCode: "EUR", regionCode: "DE")
        await store.record(id: made?.watch.id ?? UUID(), offer: offer(429), fallbackCurrency: "EUR")
        let catalog = await store.catalog()
        XCTAssertTrue(catalog.contains("[#" + (made?.watch.shortKey ?? "") + "]"), catalog)
        XCTAssertTrue(catalog.contains("PlayStation 5"), catalog)
        XCTAssertTrue(catalog.contains("goal €400"), catalog)
        XCTAssertTrue(catalog.contains("last seen"), catalog)
        XCTAssertTrue(catalog.contains("waiting"), catalog)
    }

    func testALowerPriceForAReachedTargetIsRemembered() async {
        let watch = PriceWatch(terms: ["PlayStation 5"], goal: 400, lastPrice: 420)
        XCTAssertFalse(watch.needsNotification(offer(429)))
        let reached = PriceWatch(terms: ["PlayStation 5"], goal: 400, lastPrice: 380)
        XCTAssertTrue(reached.needsNotification(offer(379)))
        XCTAssertFalse(reached.needsNotification(offer(410)))
        var notified = reached
        notified.notifiedPrice = 379
        XCTAssertFalse(notified.needsNotification(offer(379)))
        XCTAssertTrue(notified.needsNotification(offer(369)))
        let away = PriceWatch(terms: ["PlayStation 5"], goal: 400, lastPrice: 430)
        XCTAssertEqual(away.status, .waiting)
        XCTAssertFalse(away.reached)
        var paused = away
        paused.paused = true
        XCTAssertEqual(paused.status, .paused)
    }

    func testTheWatchSurvivesARelaunchOnDisk() async {
        let (store, paths) = makeStore()
        _ = await store.create(terms: ["PlayStation 5"], goal: 400, intervalHours: 12,
                               currencyCode: "EUR", regionCode: "DE",
                               wording: "PlayStation 5 unter 400 €")
        let reopened = PriceWatchStore(paths: paths)
        let watches = await reopened.all()
        XCTAssertEqual(watches.count, 1)
        XCTAssertEqual(watches.first?.terms, ["PlayStation 5"])
        XCTAssertEqual(watches.first?.goal, 400)
        XCTAssertEqual(watches.first?.intervalHours, 12)
        XCTAssertEqual(watches.first?.wording, "PlayStation 5 unter 400 €",
                       "die eigenen Worte des Nutzers müssen den Neustart überleben")
    }

    func testTheIntervalIsClampedToItsLimits() {
        XCTAssertEqual(PriceWatch.clampInterval(nil), PriceWatch.defaultIntervalHours)
        XCTAssertEqual(PriceWatch.clampInterval(1), PriceWatch.minimumIntervalHours)
        XCTAssertEqual(PriceWatch.clampInterval(1000), PriceWatch.maximumIntervalHours)
        XCTAssertEqual(PriceWatch.clampInterval(24), 24)
    }

    func testTheRefTravelsWithTheMessage() throws {
        let watch = PriceWatch(terms: ["PlayStation 5"], goal: 400, currencyCode: "EUR",
                               lastPrice: 379, lastShop: "MediaMarkt", lastURL: "https://mediamarkt.de/x",
                               hitAt: Date())
        let message = ChatMessage(role: .assistant, text: "Preisalarm", priceWatchRef: PriceWatchRef(watch: watch))
        let data = try JSONEncoder().encode(message)
        let back = try JSONDecoder().decode(ChatMessage.self, from: data)
        XCTAssertEqual(back.priceWatchRef?.product, "PlayStation 5")
        XCTAssertEqual(back.priceWatchRef?.goal, 400)
        XCTAssertEqual(back.priceWatchRef?.bestPrice, 379)
        XCTAssertEqual(back.priceWatchRef?.status, .hit)
        XCTAssertEqual(back.priceWatchRef?.isOpenable, true)
    }

    func testTheCheckerRequestCarriesTheProductGoalRegionAndSources() throws {
        let watch = PriceWatch(terms: ["PlayStation 5", "PS5"], goal: 400, wording: "PS5 mit Laufwerk unter 400 €",
                               currencyCode: "EUR", regionCode: "DE")
        let hit = Fixtures.hit("MediaMarkt", "https://mediamarkt.de/x", "mediamarkt.de",
                               "PlayStation 5 Slim — 429,00 €")
        let region = PriceRegion.located("DE")
        let context = LivePriceWatchChecker.context(watch: watch, region: region, hits: [hit])
        XCTAssertTrue(context.contains("## WATCHED PRODUCT"), context)
        XCTAssertTrue(context.contains("PlayStation 5"), context)
        XCTAssertTrue(context.contains("## TARGET PRICE"), context)
        XCTAssertTrue(context.contains("## USER REQUEST"), context)
        XCTAssertTrue(context.contains("PS5 mit Laufwerk unter 400 €"), context)
        XCTAssertTrue(context.contains("## PRICE REGION"), context)
        XCTAssertTrue(context.contains("## SOURCE [1] MediaMarkt"), context)
        let request = try LivePriceWatchChecker.makeRequest(watch: watch, region: region, hits: [hit],
                                                            credentials: credentials())
        let body = try jsonData(of: request)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let system = try XCTUnwrap(messages.first?["content"] as? String)
        XCTAssertTrue(system.contains(LivePriceWatchChecker.reportTool), system)
        XCTAssertTrue(system.contains("exactly the watched configuration"), system)
        XCTAssertTrue(system.contains("never invent a"), system)
        XCTAssertEqual(body["tool_choice"] as? String, ToolRouter.forcedChoice)
        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        let names = ToolSchemaNames.of(tools)
        XCTAssertEqual(names, [LivePriceWatchChecker.reportTool])
        let function = try XCTUnwrap(tools.first?["function"] as? [String: Any])
        let parameters = try XCTUnwrap(function["parameters"] as? [String: Any])
        let properties = try XCTUnwrap(parameters["properties"] as? [String: Any])
        XCTAssertNotNil(properties["source"], "das Modell nennt die Quelle, nicht die Adresse")
        XCTAssertNil(properties["url"], "eine Modell-Adresse darf es nicht geben")
        let required = try XCTUnwrap(parameters["required"] as? [String])
        XCTAssertTrue(required.contains("source"))
        XCTAssertTrue(required.contains("product"))
    }

    func testTheOfferIsReadFromTheReportCallAndOpensTheFetchedSource() throws {
        let arguments = #"{"price":429.99,"currency":"eur","shop":"MediaMarkt","source":2,"product":"PlayStation 5 Slim 1 TB"}"#
        let payload: [String: Any] = ["choices": [["message": ["tool_calls": [
            ["id": "c1", "type": "function", "function": ["name": LivePriceWatchChecker.reportTool,
                                                          "arguments": arguments]]
        ], "content": NSNull()]]]]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let hits = [Fixtures.hit("Otto", "https://otto.de/a", "otto.de", "PlayStation 5 — 439,00 €"),
                    Fixtures.hit("MediaMarkt", "https://mediamarkt.de/x", "mediamarkt.de",
                                 "PlayStation 5 Slim 1 TB — 429,00 €")]
        let offer = try XCTUnwrap(LivePriceWatchChecker.offer(from: data, hits: hits))
        XCTAssertEqual(offer.price, 429.99)
        XCTAssertEqual(offer.currency, "EUR")
        XCTAssertEqual(offer.shop, "MediaMarkt")
        XCTAssertEqual(offer.url, "https://mediamarkt.de/x")
        XCTAssertEqual(offer.product, "PlayStation 5 Slim 1 TB")
    }

    func testAnInventedAddressFromTheModelIsIgnored() throws {
        let arguments = #"{"price":6121.49,"currency":"EUR","shop":"cyberport.de","source":1,"product":"Mac Studio M5 Ultra 96 GB 1 TB","url":"https://www.cyberport.de/frei-erfunden-404"}"#
        let report = try XCTUnwrap(PriceWatchReport(arguments: arguments))
        let hits = [Fixtures.hit("Cyberport", "https://www.cyberport.de/eine-echte-seite", "cyberport.de",
                                 "Mac Studio 6121,49 €")]
        let offer = PriceWatchOffer(report: report, hits: hits)
        XCTAssertEqual(offer.url, "https://www.cyberport.de/eine-echte-seite",
                       "die Adresse kommt aus der gelesenen Quelle, nie aus dem Modell")
    }

    func testASourceNumberOutsideThePagesLeavesTheLinkEmpty() throws {
        let report = try XCTUnwrap(PriceWatchReport(arguments: #"{"price":429,"source":7}"#))
        let offer = PriceWatchOffer(report: report, hits: [Fixtures.hit("A", "https://a.de", "a.de", "x")])
        XCTAssertNil(offer.url)
        XCTAssertFalse(PriceWatchRef(watch: PriceWatch(terms: ["x"], goal: 1, lastURL: offer.url)).isOpenable)
    }

    func testAnOverflowingReportSourceIsRefused() {
        XCTAssertNil(PriceWatchReport(arguments: #"{"price":429,"source":-9223372036854775808}"#)?.source)
        XCTAssertNil(PriceWatchReport(arguments: #"{"price":429,"source":1e300}"#)?.source)
    }

    func testAReportWithoutAPriceIsRefused() {
        XCTAssertNil(PriceWatchReport(arguments: #"{"shop":"MediaMarkt","source":1}"#))
        XCTAssertNil(PriceWatchReport(arguments: #"{"price":0,"source":1}"#))
        XCTAssertNil(PriceWatchReport(arguments: "kein json"))
        XCTAssertEqual(PriceWatchReport(arguments: #"{"price":"429,99","shop":"Otto"}"#)?.price, 429.99)
        XCTAssertEqual(PriceWatchReport(arguments: #"{"price":429,"source":"2"}"#)?.source, 2)
        XCTAssertNil(PriceWatchReport(arguments: #"{"price":429,"source":1e300}"#)?.source)
        let payload: [String: Any] = ["choices": [["message": ["content": "kein Aufruf"]]]]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        XCTAssertNil(LivePriceWatchChecker.offer(from: data, hits: []))
    }
}
