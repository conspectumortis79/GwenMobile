import GwenMobileKit
import Foundation
import UserNotifications

@MainActor
protocol PriceWatchNotifying {
    func notify(_ watch: PriceWatch, offer: PriceWatchOffer) async -> Bool
    func prepare()
}

@MainActor
struct LocalPriceWatchNotifier: PriceWatchNotifying {
    static var delivery = NotificationDelivery()

    func prepare() {
        NotificationPermission.request(reporting: "PREISWECKER mitteilung_erlaubt")
    }

    func notify(_ watch: PriceWatch, offer: PriceWatchOffer) async -> Bool {
        let status = await Self.delivery.authorizationStatus()
        guard status == .authorized || status == .provisional else {
            flowMark("PREISWECKER mitteilung nicht_erlaubt status=\(status.rawValue)")
            return false
        }
        let content = UNMutableNotificationContent()
        content.title = PriceWatchAnswers.notifyTitle(watch)
        content.body = PriceWatchAnswers.notifyBody(watch, offer: offer)
        content.sound = .default
        content.userInfo = ["watch": watch.shortKey]
        let request = UNNotificationRequest(identifier: "gwen.pricewatch." + watch.shortKey,
                                            content: content, trigger: nil)
        do {
            try await Self.delivery.deliver(request)
            return true
        } catch {
            flowMark("PREISWECKER mitteilung fehler=\(error.localizedDescription)")
            return false
        }
    }
}

@MainActor
final class PriceWatchDesk: ObservableObject {
    func checker(onStatus: @escaping (String?) -> Void) -> any PriceWatchChecking {
        #if DEBUG
        if let kept { return kept }
        #endif
        return LivePriceWatchChecker(lookup: WebPriceLookup(onStatus: onStatus))
    }

    func notifier() -> any PriceWatchNotifying {
        #if DEBUG
        if let keptNotifier { return keptNotifier }
        #endif
        return LocalPriceWatchNotifier()
    }

    #if DEBUG
    private var kept: (any PriceWatchChecking)?
    private var keptNotifier: (any PriceWatchNotifying)?

    func stand(in checker: any PriceWatchChecking, notifier: (any PriceWatchNotifying)? = nil) {
        kept = checker
        if let notifier { keptNotifier = notifier }
    }

    func restore() {
        kept = nil
        keptNotifier = nil
    }
    #endif
}

@MainActor
struct PriceWatchFlowRunner {
    let store: PriceWatchStore
    let checker: any PriceWatchChecking
    let credentials: PriceWatchCredentials
    let notifier: any PriceWatchNotifying

    func run(_ request: PriceWatchRequest, question: String, now: Date = Date()) async -> PriceWatchOutcome {
        switch request.action {
        case .create:
            return await create(request, question: question, now: now)
        case .update:
            return await update(request, now: now)
        case .delete:
            return await delete(request)
        case .list:
            return PriceWatchOutcome(text: PriceWatchAnswers.list(await store.all()), ref: nil)
        case .check:
            return await checkNow(request, now: now)
        }
    }

    func checkDue(now: Date = Date()) async -> [PriceWatchCheckOutcome] {
        var hits: [PriceWatchCheckOutcome] = []
        for watch in await store.due(now: now) {
            guard !Task.isCancelled else { break }
            let outcome = await check(watch, now: now)
            if outcome.hit { hits.append(outcome) }
        }
        return hits
    }

    func checkOne(id: UUID, now: Date = Date()) async -> PriceWatchCheckOutcome? {
        guard let watch = await store.watch(id: id) else { return nil }
        return await check(watch, now: now)
    }

    private func create(_ request: PriceWatchRequest, question: String, now: Date) async -> PriceWatchOutcome {
        guard let goal = request.goal else { return PriceWatchOutcome(text: PriceWatchAnswers.needGoal(), ref: nil) }
        let region = PriceRegion.claimed(request.country, in: question) ?? PriceRegion.device()
        guard let made = await store.create(terms: request.terms, goal: goal,
                                            intervalHours: request.intervalHours,
                                            currencyCode: region.currencyCode,
                                            regionCode: region.code, wording: question, now: now) else {
            return PriceWatchOutcome(text: PriceWatchAnswers.missing(request.terms), ref: nil)
        }
        notifier.prepare()
        let outcome = await check(made.watch, now: now)
        flowMarkPersonal("PREISWECKER angelegt neu=\(made.created) produkt=\(TextLine.oneLine(made.watch.product, limit: 40)) "
                         + "ziel=\(Formatters.price(made.watch.goal, currency: made.watch.currencyCode)) "
                         + "intervall=\(made.watch.intervalHours)h \(region.traceLine)")
        return PriceWatchOutcome(text: PriceWatchAnswers.saved(outcome, created: made.created),
                                 ref: PriceWatchRef(watch: outcome.watch))
    }

    private func update(_ request: PriceWatchRequest, now: Date) async -> PriceWatchOutcome {
        guard let changed = await store.update(key: request.key, terms: request.terms, goal: request.goal,
                                               intervalHours: request.intervalHours, now: now) else {
            return PriceWatchOutcome(text: PriceWatchAnswers.missing(request.terms), ref: nil)
        }
        let outcome = await check(changed, now: now)
        flowMarkPersonal("PREISWECKER geaendert produkt=\(TextLine.oneLine(changed.product, limit: 40)) "
                         + "ziel=\(Formatters.price(changed.goal, currency: changed.currencyCode)) "
                         + "intervall=\(changed.intervalHours)h")
        return PriceWatchOutcome(text: PriceWatchAnswers.saved(outcome, created: false),
                                 ref: PriceWatchRef(watch: outcome.watch))
    }

    private func delete(_ request: PriceWatchRequest) async -> PriceWatchOutcome {
        guard let gone = await store.delete(key: request.key, terms: request.terms) else {
            return PriceWatchOutcome(text: PriceWatchAnswers.missing(request.terms), ref: nil)
        }
        flowMarkPersonal("PREISWECKER geloescht produkt=\(TextLine.oneLine(gone.product, limit: 40))")
        return PriceWatchOutcome(text: PriceWatchAnswers.deleted(gone), ref: nil)
    }

    private func checkNow(_ request: PriceWatchRequest, now: Date) async -> PriceWatchOutcome {
        guard let watch = await store.match(key: request.key, terms: request.terms) else {
            return PriceWatchOutcome(text: PriceWatchAnswers.missing(request.terms), ref: nil)
        }
        let outcome = await check(watch, now: now)
        return PriceWatchOutcome(text: PriceWatchAnswers.checked(outcome),
                                 ref: PriceWatchRef(watch: outcome.watch))
    }

    private func check(_ watch: PriceWatch, now: Date) async -> PriceWatchCheckOutcome {
        do {
            let offer = try await checker.check(watch, credentials: credentials)
            await store.record(id: watch.id, offer: offer, fallbackCurrency: watch.currencyCode, now: now)
            var fresh = await store.watch(id: watch.id) ?? watch
            if let offer, fresh.needsNotification(offer) {
                if await notifier.notify(fresh, offer: offer) {
                    await store.markNotified(id: fresh.id, price: offer.price)
                    fresh = await store.watch(id: fresh.id) ?? fresh
                    flowMarkPersonal("PREISWECKER alarm produkt=\(TextLine.oneLine(fresh.product, limit: 40)) "
                                     + "\(offer.traceLine)")
                } else {
                    flowMarkPersonal("PREISWECKER alarm nicht_zugestellt produkt="
                                     + TextLine.oneLine(fresh.product, limit: 40))
                }
            }
            return PriceWatchCheckOutcome(watch: fresh, offer: offer, failure: nil)
        } catch {
            await store.record(id: watch.id, offer: nil, fallbackCurrency: watch.currencyCode, now: now)
            let fresh = await store.watch(id: watch.id) ?? watch
            flowMarkPersonal("PREISWECKER fehlgeschlagen produkt=\(TextLine.oneLine(watch.product, limit: 40)) "
                             + "grund=\(TextLine.oneLine(error.localizedDescription, limit: 120))")
            return PriceWatchCheckOutcome(watch: fresh, offer: nil, failure: error.localizedDescription)
        }
    }
}
