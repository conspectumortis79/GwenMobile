import GwenMobileKit

struct PriceWatchCheckOutcome: Equatable, Sendable {
    var watch: PriceWatch
    var offer: PriceWatchOffer?
    var failure: String?

    var hit: Bool { offer.map { watch.accepts($0) && $0.price <= watch.goal } ?? false }
}

struct PriceWatchOutcome: Equatable, Sendable {
    var text: String
    var ref: PriceWatchRef?
}

enum PriceWatchAnswers {
    static func alarm(_ watch: PriceWatch, offer: PriceWatchOffer) -> String {
        let price = Formatters.price(offer.price, currency: offer.currency.isEmpty
            ? watch.currencyCode : offer.currency)
        let goal = Formatters.price(watch.goal, currency: watch.currencyCode ?? offer.currency)
        var text = L.fmt2("price_watch_alarm", watch.product, price)
        if !offer.shop.isEmpty { text += " " + L.fmt("price_watch_alarm_shop", offer.shop) }
        return text + " " + L.fmt("price_watch_alarm_goal", goal)
    }

    static func checkFailed(_ outcome: PriceWatchCheckOutcome) -> String {
        let reason = outcome.failure ?? L.t("err_generic")
        return L.fmt("price_watch_check_failed", TextLine.oneLine(reason, limit: 160))
    }

    static func checked(_ outcome: PriceWatchCheckOutcome) -> String {
        resolved(outcome) { watch, offer, price in
            let goal = Formatters.price(watch.goal, currency: watch.currencyCode)
            var text = L.fmt2("price_watch_checked_waiting", price, goal)
            if !offer.shop.isEmpty { text += " " + L.fmt("price_watch_alarm_shop", offer.shop) }
            return text
        }
    }

    static func currentLine(_ outcome: PriceWatchCheckOutcome) -> String? {
        resolved(outcome) { _, offer, price in
            guard !offer.shop.isEmpty else { return L.fmt("price_watch_now", price) }
            return L.fmt("price_watch_now", L.fmt2("price_watch_at_shop", price, offer.shop))
        }
    }

    private static func resolved(_ outcome: PriceWatchCheckOutcome,
                                 offerLine: (PriceWatch, PriceWatchOffer, String) -> String) -> String {
        if outcome.hit, let offer = outcome.offer { return alarm(outcome.watch, offer: offer) }
        if outcome.failure != nil { return checkFailed(outcome) }
        guard let offer = outcome.offer else {
            return L.fmt("price_watch_no_price", outcome.watch.product)
        }
        let price = Formatters.price(offer.price, currency: offer.currency.isEmpty
            ? outcome.watch.currencyCode : offer.currency)
        return offerLine(outcome.watch, offer, price)
    }

    static func deleted(_ watch: PriceWatch) -> String {
        L.fmt("price_watch_deleted", watch.product)
    }

    static func empty() -> String {
        L.t("price_watch_none")
    }

    static func list(_ watches: [PriceWatch]) -> String {
        guard !watches.isEmpty else { return empty() }
        var lines = [L.t("price_watch_list_head")]
        lines += watches.map(listLine(_:))
        return lines.joined(separator: "\n")
    }

    static func listLine(_ watch: PriceWatch) -> String {
        var details = L.fmt("price_watch_list_goal", Formatters.price(watch.goal,
                                                                     currency: watch.currencyCode))
        details += ", " + L.t("price_watch_status_" + watch.status.rawValue)
        if let price = watch.lastPrice {
            let seen = Formatters.price(price, currency: watch.lastCurrency ?? watch.currencyCode)
            if let shop = watch.lastShop, !shop.isEmpty {
                details += ", " + L.fmt2("price_watch_list_seen_at", seen, shop)
            } else {
                details += ", " + L.fmt("price_watch_list_seen", seen)
            }
        } else if let checked = watch.lastCheckedAt {
            details += ", " + L.fmt("price_watch_list_checked", Formatters.eventChip(checked))
        }
        return L.fmt2("price_watch_list_line", watch.product, details)
    }

    static func missing(_ terms: [String]) -> String {
        guard let first = terms.first, !first.isEmpty else { return L.t("price_watch_missing") }
        return L.fmt("price_watch_missing_for", first)
    }

    static func needGoal() -> String {
        L.t("price_watch_need_goal")
    }

    static func notifyBody(_ watch: PriceWatch, offer: PriceWatchOffer) -> String {
        let price = Formatters.price(offer.price, currency: offer.currency.isEmpty
            ? watch.currencyCode : offer.currency)
        let atShop = offer.shop.isEmpty ? price : L.fmt2("price_watch_at_shop", price, offer.shop)
        let goal = Formatters.price(watch.goal, currency: watch.currencyCode ?? offer.currency)
        return L.fmt2("price_watch_notify_body", atShop, goal)
    }

    static func notifyTitle(_ watch: PriceWatch) -> String {
        L.fmt("price_watch_notify_title", watch.product)
    }

    static func saved(_ outcome: PriceWatchCheckOutcome, created: Bool) -> String {
        let watch = outcome.watch
        let goal = Formatters.price(watch.goal, currency: watch.currencyCode)
        var text = created ? L.fmt2("price_watch_created", watch.product, goal)
                           : L.fmt2("price_watch_updated", watch.product, goal)
        if let line = currentLine(outcome) {
            text += " " + line
        }
        return text
    }
}
