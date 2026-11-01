@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import Foundation
import UserNotifications

@MainActor
private final class ProbePriceWatchNotifier: PriceWatchNotifying {
    private(set) var notified: [PriceWatch] = []

    func prepare() {}

    func notify(_ watch: PriceWatch, offer: PriceWatchOffer) async -> Bool {
        notified.append(watch)
        return true
    }
}

@MainActor
enum DebugPriceWatchProbe {
    private enum Expectation {
        case watch(PriceWatchAction, goal: Double?)
        case price
        case other
    }

    private struct WatchCase {
        let text: String
        let expected: Expectation
        let needsCatalog: Bool
        let step: String
    }

    private static let watchCases = [
        WatchCase(text: "Sag mir Bescheid, wenn die PlayStation 5 unter 400 € fällt.",
                  expected: .watch(.create, goal: 400), needsCatalog: false, step: "create"),
        WatchCase(text: "Beobachte die Kopfhörer Aura X unter 199 €.",
                  expected: .watch(.create, goal: 199), needsCatalog: false, step: "create"),
        WatchCase(text: "Welche Preis-Wecker habe ich?",
                  expected: .watch(.list, goal: nil), needsCatalog: true, step: "list"),
        WatchCase(text: "Prüfe jetzt den Preis-Wecker für die PlayStation 5.",
                  expected: .watch(.check, goal: nil), needsCatalog: true, step: "check"),
        WatchCase(text: "Lösche den Preis-Wecker für die Kopfhörer Aura X.",
                  expected: .watch(.delete, goal: nil), needsCatalog: true, step: "delete"),
        WatchCase(text: "Ändere den Preis-Wecker für die PS5 auf 350 €.",
                  expected: .watch(.update, goal: 350), needsCatalog: true, step: "update"),
        WatchCase(text: "Was kostet die PlayStation 5 gerade?",
                  expected: .price, needsCatalog: false, step: "compare"),
        WatchCase(text: "Findest du das MacBook Pro 14 günstiger?",
                  expected: .price, needsCatalog: false, step: "compare"),
        WatchCase(text: "Wie viele Preise hat Roger Federer gewonnen?",
                  expected: .other, needsCatalog: false, step: "chat")
    ]

    private static let catalog = "[#abcd1234] PlayStation 5 (goal 400.00 EUR, waiting)\n"
        + "[#efab5678] Kopfhörer Aura X (goal 199.00 EUR, waiting)"

    static func run(_ view: ChatView) async {
        let report = SweepReport(file: "price_watch.txt")
        report.add("KONFIG", "schluessel=\(view.settings.isConfigured) chat=\(view.settings.chatModel) "
                   + "basis=\(view.settings.baseURL)")
        await routing(view, report: report)
        await caseStudy(view, report: report)
        await storeRoundTrip(report: report)
        await flow(view, report: report)
        await notification(report: report)
        flowLog.info("PREISWECKER fertig")
    }

    private static func routing(_ view: ChatView, report: SweepReport) async {
        var right = 0
        var wrongWatch = 0
        var wrongCompare = 0
        for (index, item) in watchCases.enumerated() {
            let decision = await ToolRouter.decide(RouterAsk(baseURL: view.settings.baseURL,
                                                             key: view.settings.apiKey,
                                                             model: view.settings.chatModel,
                                                             text: item.text, context: SendContext(),
                                                             history: [], thinking: .nothing,
                                                             watchCatalog: item.needsCatalog ? catalog : ""))
            let fits = matches(decision, item)
            if fits { right += 1 }
            if case .priceWatch = decision?.route, !wantsWatch(item) { wrongWatch += 1 }
            if case .priceSearch = decision?.route, !wantsPrice(item) { wrongCompare += 1 }
            report.add("ROUTER_\(index + 1)",
                       "passt=\(fits) erwartet=\(item.step) gewaehlt=\(describe(decision)) "
                       + "katalog=\(item.needsCatalog) satz=\(TextLine.oneLine(item.text, limit: 60))")
        }
        report.add("ROUTER_SUMME", "richtig=\(right)/\(watchCases.count) "
                   + "wecker_falsch=\(wrongWatch) vergleich_falsch=\(wrongCompare)")
    }

    private static func caseStudy(_ view: ChatView, report: SweepReport) async {
        let sentence = "Bitte ein Preisecker machen für M5 Ultra 30 C 64 C 256 GB ein Terabyte, "
            + "wenn es unter 10.000 Euro fällt."
        report.add("FALL_SATZ", TextLine.oneLine(sentence, limit: 90))
        let plan = await ToolRouter.plan(RouterAsk(baseURL: view.settings.baseURL, key: view.settings.apiKey,
                                                   model: view.settings.chatModel, text: sentence,
                                                   context: SendContext(), history: [], thinking: .nothing))
        report.add("FALL_PLAN", "kette=\(plan.traceLine) schritte=\(plan.actions.count) "
                   + "eine_antwort=\(plan.merges)")
        guard case .priceWatch(let request) = plan.primary.route, let goal = request.goal else {
            report.add("FALL_PLAN_TREFFER", "kein wecker — erwartet genau einer")
            return
        }
        report.add("FALL_TERMS", "ziel=\(goal) begriffe=\(request.terms.joined(separator: " | "))")
        let watch = PriceWatch(terms: request.terms, goal: goal, wording: sentence,
                               currencyCode: "EUR", regionCode: "DE")
        let credentials = PriceWatchCredentials(baseURL: view.settings.baseURL, key: view.settings.apiKey,
                                                model: view.settings.chatModel,
                                                thinking: view.settings.thinkingOffDirective(
                                                    for: view.settings.chatModel))
        let region = PriceRegion.located("DE")
        do {
            let hits = try await WebPriceLookup { _ in }.hits(for: watch.terms, region: region)
            let extractionRequest = try LivePriceWatchChecker.makeRequest(watch: watch, region: region,
                                                                          hits: hits,
                                                                          credentials: credentials)
            let data = try await HTTP.jsonData(extractionRequest)
            guard let offer = LivePriceWatchChecker.offer(from: data, hits: hits) else {
                report.add("FALL_ANGEBOT", "kein angebot — die quellen zeigen keine passende konfiguration")
                return
            }
            report.add("FALL_ANGEBOT", "\(offer.traceLine)")
            report.add("FALL_QUELLE", "url=\(TextLine.oneLine(offer.url ?? "-", limit: 120)) "
                       + "status=\(await status(of: offer.url)) "
                       + "im_treffer_satz=\(offer.url != nil)")
            let wanted = numbers(in: request.terms.joined(separator: " "))
            let found = numbers(in: offer.product)
            let missing = wanted.subtracting(found)
            report.add("FALL_KONFIG", "erwartet=\(wanted.sorted().joined(separator: ",")) "
                       + "angebot=\(found.sorted().joined(separator: ",")) "
                       + "fehlt=\(missing.sorted().joined(separator: ",")) "
                       + "produkt=\(TextLine.oneLine(offer.product, limit: 60))")
        } catch {
            report.addFailure("FALL_ANGEBOT", error)
        }
    }

    private static func numbers(in text: String) -> Set<String> {
        Set(text.split(whereSeparator: { !$0.isNumber }).map(String.init).filter { !$0.isEmpty })
    }

    private static func status(of url: String?) async -> String {
        guard let url, let parsed = URL(string: url) else { return "-" }
        var request = URLRequest(url: parsed, timeoutInterval: 20)
        request.httpMethod = "GET"
        request.setValue(WebSearch.searchUA, forHTTPHeaderField: "User-Agent")
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return "fehler" }
        return "\(http.statusCode)"
    }

    private static func storeRoundTrip(report: SweepReport) async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("gwen-pricewatch-probe-" + UUID().uuidString)
        let paths = StoragePaths(documents: root.appendingPathComponent("Documents"),
                                 support: root.appendingPathComponent("Support"))
        let store = PriceWatchStore(paths: paths)
        let start = Date()
        let made = await store.create(terms: ["PlayStation 5"], goal: 400, intervalHours: 6,
                                      currencyCode: "EUR", regionCode: "DE", now: start)
        let id = made?.watch.id ?? UUID()
        report.add("SPEICHER", "angelegt=\(made?.created ?? false) schluessel=\(made?.watch.shortKey ?? "-") "
                   + "intervall=\(made?.watch.intervalHours ?? -1)")
        let offer = PriceWatchOffer(price: 379, currency: "EUR", shop: "MediaMarkt",
                                    url: "https://mediamarkt.de/x")
        await store.record(id: id, offer: offer, fallbackCurrency: "EUR", now: start)
        var fresh = await store.watch(id: id)
        report.add("TREFFER", "erreicht=\(fresh?.reached ?? false) status=\(fresh?.status.rawValue ?? "-") "
                   + "preis=\(fresh?.lastPrice ?? -1) melden=\(fresh?.needsNotification(offer) ?? false)")
        await store.markNotified(id: id, price: 379)
        fresh = await store.watch(id: id)
        report.add("MELDUNG", "erneut=\(fresh?.needsNotification(offer) ?? false) "
                   + "tiefer=\(fresh?.needsNotification(PriceWatchOffer(price: 359, currency: "EUR")) ?? false)")
        let dueBefore = await store.due(now: start.addingTimeInterval(5 * 3600))
        let dueAfter = await store.due(now: start.addingTimeInterval(7 * 3600))
        report.add("FRIST", "vorher=\(dueBefore.count) nachher=\(dueAfter.count) "
                   + "naechste=\(await store.nextDueDate().map { Formatters.eventDateTime($0) } ?? "-")")
        await store.setPaused(id: id, paused: true)
        report.add("PAUSE", "faellig=\(await store.due(now: start.addingTimeInterval(7 * 3600)).count) "
                   + "ohne_naechste=\(await store.nextDueDate() == nil)")
        report.add("KATALOG", TextLine.oneLine(await store.catalog(), limit: 160))
        let reopened = PriceWatchStore(paths: paths)
        let persisted = await reopened.all()
        report.add("NEUSTART", "eintraege=\(persisted.count) ziel=\(persisted.first?.goal ?? -1) "
                   + "pausiert=\(persisted.first?.paused ?? false)")
        let gone = await reopened.delete(key: made?.watch.shortKey, terms: [])
        report.add("LOESCHEN", "geloescht=\(gone != nil) rest=\(await reopened.count())")
        try? FileManager.default.removeItem(at: root)
    }

    private static func flow(_ view: ChatView, report: SweepReport) async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("gwen-pricewatch-flow-" + UUID().uuidString)
        let paths = StoragePaths(documents: root.appendingPathComponent("Documents"),
                                 support: root.appendingPathComponent("Support"))
        let store = PriceWatchStore(paths: paths)
        let notifier = ProbePriceWatchNotifier()
        let checker = LivePriceWatchChecker(lookup: WebPriceLookup { _ in })
        view.store.stand(in: store)
        view.priceWatchDesk.stand(in: checker, notifier: notifier)
        let known = Set(view.store.conversations.map(\.id))
        let sentence = "Sag mir Bescheid, wenn die PlayStation 5 unter 1000 € fällt."
        report.add("ABLAUF_SATZ", sentence)
        let started = ContinuousClock.now
        view.input = sentence
        await view.send()
        let answer = view.lastAnswer
        let ref = answer?.priceWatchRef
        let watches = await store.all()
        let messages = view.store.current?.messages ?? []
        report.add("ABLAUF_ANTWORT", "ms=\(msOf(started.duration(to: .now))) "
                   + "wecker=\(watches.count) meldungen=\(notifier.notified.count) "
                   + "karte=\(ref?.product ?? "-") ziel=\(ref?.goal ?? -1) "
                   + "preis=\(ref?.bestPrice ?? -1) status=\(ref?.status.rawValue ?? "-") "
                   + "link=\(ref?.isOpenable ?? false) "
                   + "text=\(TextLine.oneLine(answer?.text ?? "", limit: 220))")
        report.add("ABLAUF_CHAT", "nachrichten=\(messages.count) "
                   + "karte_am_msg=\(messages.contains { $0.priceWatchRef != nil }) "
                   + "plan=\(view.probeLastPlan?.traceLine ?? "-")")
        if let watch = watches.first, let price = watch.lastPrice {
            let offer = PriceWatchOffer(price: price, currency: watch.lastCurrency ?? "EUR",
                                        shop: watch.lastShop ?? "", url: watch.lastURL)
            report.add("ABLAUF_LIVE", "produkt=\(TextLine.oneLine(watch.product, limit: 60)) "
                       + "preis=\(price) laden=\(watch.lastShop ?? "-") "
                       + "region=\(watch.regionCode ?? "-") treffer=\(watch.reached)")
            await notificationLines(watch: watch, offer: offer, report: report)
        } else {
            report.add("ABLAUF_LIVE", "kein preis gefunden — netz oder modell lieferten nichts")
        }
        let list = await view.ask("Welche Preis-Wecker habe ich?", fresh: true)
        report.add("ABLAUF_LISTE", "text=\(TextLine.oneLine(list?.text ?? "", limit: 200))")
        let removed = await view.ask("Lösche den Preis-Wecker für die PlayStation 5", fresh: true)
        report.add("ABLAUF_LOESCHEN", "wecker=\(await store.count()) "
                   + "text=\(TextLine.oneLine(removed?.text ?? "", limit: 140))")
        view.priceWatchDesk.restore()
        view.store.restoreWatches()
        var dropped = 0
        for conversation in view.store.conversations where !known.contains(conversation.id) {
            if view.store.removeConversation(conversation.id) != nil { dropped += 1 }
        }
        try? FileManager.default.removeItem(at: root)
        await PriceWatchBackground.scheduleNext()
        report.add("AUFRAEUMEN", "probe_chats_entfernt=\(dropped) wecker=\(await view.store.watches.count())")
    }

    private static func notification(report: SweepReport) async {
        let watch = PriceWatch(terms: ["GwenMobile Probe (kein echtes Produkt)"], goal: 1000,
                               currencyCode: "EUR")
        LocalPriceWatchNotifier().prepare()
        _ = await LocalPriceWatchNotifier().notify(watch, offer: PriceWatchOffer(price: 429, currency: "EUR",
                                                                                shop: "Probe-Shop"))
        let identifier = "gwen.pricewatch." + watch.shortKey
        _ = await ProbeWait.poll(10) {
            await UNUserNotificationCenter.current().deliveredNotifications()
                .contains { $0.request.identifier == identifier }
        }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
        let mine = delivered.filter { $0.request.identifier == identifier }
        report.add("MITTEILUNG", "erlaubnis=\(settings.authorizationStatus.rawValue) "
                   + "zugestellt=\(delivered.count) probe=\(mine.count) "
                   + "probe_text=\(TextLine.oneLine(mine.first?.request.content.body ?? "-", limit: 120))")
    }

    private static func notificationLines(watch: PriceWatch, offer: PriceWatchOffer,
                                          report: SweepReport) async {
        LocalPriceWatchNotifier().prepare()
        _ = await LocalPriceWatchNotifier().notify(watch, offer: offer)
        let identifier = "gwen.pricewatch." + watch.shortKey
        _ = await ProbeWait.poll(10) {
            await UNUserNotificationCenter.current().deliveredNotifications()
                .contains { $0.request.identifier == identifier }
        }
        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
        let mine = delivered.filter { $0.request.identifier == identifier }
        report.add("ABLAUF_MITTEILUNG", "zugestellt=\(mine.count) "
                   + "titel=\(TextLine.oneLine(mine.first?.request.content.title ?? "-", limit: 80))")
    }

    private static func wantsWatch(_ item: WatchCase) -> Bool {
        if case .watch = item.expected { return true }
        return false
    }

    private static func wantsPrice(_ item: WatchCase) -> Bool {
        if case .price = item.expected { return true }
        return false
    }

    private static func matches(_ decision: ToolDecision?, _ item: WatchCase) -> Bool {
        guard let decision else { return false }
        switch (item.expected, decision.route) {
        case (.watch(let action, let goal), .priceWatch(let request)):
            guard request.action == action else { return false }
            guard let goal else { return true }
            return request.goal.map { abs($0 - goal) < 0.5 } ?? false
        case (.price, .priceSearch):
            return true
        case (.other, .chat):
            return true
        default:
            return false
        }
    }

    private static func describe(_ decision: ToolDecision?) -> String {
        switch decision?.route {
        case .some(.priceWatch(let request)):
            return "wecker/\(request.action.rawValue) ziel=\(request.goal ?? -1) "
                + "intervalle=\(request.intervalHours ?? -1) "
                + "begriffe=\(TextLine.oneLine(request.terms.joined(separator: "|"), limit: 40))"
        case .some(.priceSearch(let terms, _, _)):
            return "vergleich begriffe=\(TextLine.oneLine(terms.joined(separator: "|"), limit: 40))"
        default:
            return RouteSweep.describe(decision)
        }
    }
}
#endif
