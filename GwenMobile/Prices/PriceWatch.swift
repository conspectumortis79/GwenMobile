import GwenMobileKit
import Foundation

enum PriceWatchAction: String, Equatable, Sendable {
    case create
    case update
    case delete
    case check
    case list
}

struct PriceWatchRequest: Equatable, Sendable {
    var action: PriceWatchAction
    var terms: [String] = []
    var goal: Double? = nil
    var country: String? = nil
    var intervalHours: Int? = nil
    var key: String? = nil

    var stepWords: String {
        StepWords.joined(action.rawValue, terms.first,
                         goal.map { Formatters.price($0, currency: nil) },
                         intervalHours.map { "\($0)h" }, key.map { "#" + $0 })
    }
}

struct PriceWatch: Codable, Identifiable, Hashable, Sendable {
    enum Status: String, Codable, Equatable, Sendable {
        case waiting
        case hit
        case paused
    }

    static let defaultIntervalHours = 24
    static let minimumIntervalHours = 6
    static let maximumIntervalHours = 168
    static let maximumGoal = 1_000_000.0
    static let maxTerms = 3
    static let maxTermChars = 80
    static let maxShopChars = 60

    var id: UUID
    var terms: [String]
    var wording: String
    var goal: Double
    var currencyCode: String?
    var regionCode: String?
    var intervalHours: Int
    var paused: Bool
    var createdAt: Date
    var updatedAt: Date
    var lastCheckedAt: Date?
    var lastPrice: Double?
    var lastCurrency: String?
    var lastShop: String?
    var lastURL: String?
    var lastProduct: String?
    var hitAt: Date?
    var notifiedPrice: Double?

    enum CodingKeys: String, CodingKey {
        case id, terms, wording, goal, currencyCode, regionCode, intervalHours, paused, createdAt, updatedAt,
             lastCheckedAt, lastPrice, lastCurrency, lastShop, lastURL, lastProduct, hitAt, notifiedPrice
    }

    init(terms: [String], goal: Double, wording: String = "", currencyCode: String? = nil,
         regionCode: String? = nil,
         intervalHours: Int = PriceWatch.defaultIntervalHours, paused: Bool = false,
         createdAt: Date = Date(), updatedAt: Date = Date(), lastCheckedAt: Date? = nil,
         lastPrice: Double? = nil, lastCurrency: String? = nil, lastShop: String? = nil,
         lastURL: String? = nil, lastProduct: String? = nil, hitAt: Date? = nil, notifiedPrice: Double? = nil,
         id: UUID = UUID()) {
        self.id = id
        self.terms = terms
        self.wording = wording
        self.goal = goal
        self.currencyCode = currencyCode
        self.regionCode = regionCode
        self.intervalHours = intervalHours
        self.paused = paused
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastCheckedAt = lastCheckedAt
        self.lastPrice = lastPrice
        self.lastCurrency = lastCurrency
        self.lastShop = lastShop
        self.lastURL = lastURL
        self.lastProduct = lastProduct
        self.hitAt = hitAt
        self.notifiedPrice = notifiedPrice
    }

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        id = try fields.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        terms = try fields.decodeIfPresent([String].self, forKey: .terms) ?? []
        wording = try fields.decodeIfPresent(String.self, forKey: .wording) ?? ""
        goal = try fields.decodeIfPresent(Double.self, forKey: .goal) ?? 0
        currencyCode = try fields.decodeIfPresent(String.self, forKey: .currencyCode)
        regionCode = try fields.decodeIfPresent(String.self, forKey: .regionCode)
        intervalHours = try fields.decodeIfPresent(Int.self, forKey: .intervalHours)
            ?? Self.defaultIntervalHours
        paused = try fields.decodeIfPresent(Bool.self, forKey: .paused) ?? false
        createdAt = try fields.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try fields.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        lastCheckedAt = try fields.decodeIfPresent(Date.self, forKey: .lastCheckedAt)
        lastPrice = try fields.decodeIfPresent(Double.self, forKey: .lastPrice)
        lastCurrency = try fields.decodeIfPresent(String.self, forKey: .lastCurrency)
        lastShop = try fields.decodeIfPresent(String.self, forKey: .lastShop)
        lastURL = try fields.decodeIfPresent(String.self, forKey: .lastURL)
        lastProduct = try fields.decodeIfPresent(String.self, forKey: .lastProduct)
        hitAt = try fields.decodeIfPresent(Date.self, forKey: .hitAt)
        notifiedPrice = try fields.decodeIfPresent(Double.self, forKey: .notifiedPrice)
    }

    var shortKey: String { EntityKey.short(id) }

    var product: String { terms.first ?? "" }

    var reached: Bool {
        guard let lastPrice else { return false }
        guard let own = currencyCode?.uppercased(), !own.isEmpty,
              let seen = lastCurrency?.uppercased(), !seen.isEmpty else {
            return lastPrice <= goal
        }
        return seen == own && lastPrice <= goal
    }

    func accepts(_ offer: PriceWatchOffer) -> Bool {
        let seen = offer.currency.uppercased()
        guard !seen.isEmpty, let own = currencyCode?.uppercased(), !own.isEmpty else { return true }
        return seen == own
    }

    var status: Status {
        if paused { return .paused }
        return reached ? .hit : .waiting
    }

    var nextDue: Date {
        (lastCheckedAt ?? createdAt).addingTimeInterval(Double(intervalHours) * 3600)
    }

    func isDue(now: Date) -> Bool { !paused && nextDue <= now }

    func needsNotification(_ offer: PriceWatchOffer) -> Bool {
        guard accepts(offer), offer.price <= goal else { return false }
        guard let notifiedPrice else { return true }
        return offer.price < notifiedPrice - 0.005
    }

    func matches(key: String?, terms wanted: [String]) -> Bool {
        if let key, !key.isEmpty, key.caseInsensitiveCompare(shortKey) == .orderedSame { return true }
        let folded = Set(wanted.map { PriceWatch.fold($0) }.filter { !$0.isEmpty })
        guard !folded.isEmpty else { return false }
        return !Set(terms.map { PriceWatch.fold($0) }).isDisjoint(with: folded)
    }

    nonisolated static func fold(_ raw: String) -> String {
        raw.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .trimmed
    }

    nonisolated static func cleanTerms(_ raw: [String]) -> [String] {
        PriceSources.uniqueTerms(raw, limit: maxTerms, chars: maxTermChars) { fold($0) == fold($1) }
    }

    nonisolated static func cleanWording(_ raw: String) -> String {
        TextLine.oneLine(raw, limit: 200).trimmed
    }

    nonisolated static func clampInterval(_ hours: Int?) -> Int {
        guard let hours else { return defaultIntervalHours }
        return min(max(hours, minimumIntervalHours), maximumIntervalHours)
    }
}

struct PriceWatchRef: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var product: String
    var goal: Double
    var currencyCode: String?
    var bestPrice: Double?
    var bestShop: String?
    var bestURL: String?
    var bestProduct: String?
    var status: PriceWatch.Status
    var checkedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, product, goal, currencyCode, bestPrice, bestShop, bestURL, bestProduct, status, checkedAt
    }

    init(watch: PriceWatch) {
        id = watch.id
        product = watch.product
        goal = watch.goal
        currencyCode = watch.currencyCode ?? watch.lastCurrency
        bestPrice = watch.lastPrice
        bestShop = watch.lastShop
        bestURL = watch.lastURL
        bestProduct = watch.lastProduct
        status = watch.status
        checkedAt = watch.lastCheckedAt
    }

    init(from decoder: Decoder) throws {
        let fields = try LenientFields<CodingKeys>(decoder)
        id = fields.metadata(UUID.self, .id, fallback: UUID())
        product = fields.content(String.self, .product, fallback: "")
        goal = fields.content(Double.self, .goal, fallback: 0)
        currencyCode = fields.metadata(String.self, .currencyCode)
        bestPrice = fields.metadata(Double.self, .bestPrice)
        bestShop = fields.metadata(String.self, .bestShop)
        bestURL = fields.metadata(String.self, .bestURL)
        bestProduct = fields.metadata(String.self, .bestProduct)
        status = fields.metadata(PriceWatch.Status.self, .status, fallback: .waiting)
        checkedAt = fields.metadata(Date.self, .checkedAt)
    }

    var isUsable: Bool { !product.isEmpty && goal > 0 }

    var isOpenable: Bool {
        guard let bestURL, !bestURL.isEmpty else { return false }
        return URL(string: bestURL) != nil
    }

    var goalText: String { Formatters.price(goal, currency: currencyCode) }

    var bestText: String? {
        guard let bestPrice else { return nil }
        let price = Formatters.price(bestPrice, currency: currencyCode)
        guard let bestShop, !bestShop.isEmpty else { return price }
        return L.fmt2("price_watch_at_shop", price, bestShop)
    }

    var statusText: String { L.t("price_watch_status_" + status.rawValue) }

    var chipStamp: String? {
        guard let checkedAt else { return nil }
        return L.fmt("price_watch_checked_at", Formatters.eventChip(checkedAt))
    }
}

struct PriceWatchReport: Equatable, Sendable {
    var price: Double
    var currency: String
    var shop: String
    var source: Int?
    var product: String

    init?(arguments: String) {
        guard let data = arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let price = LooseNumber.value(object["price"]), price > 0, price <= PriceWatch.maximumGoal else {
            return nil
        }
        self.price = price
        currency = Self.text(object["currency"]).uppercased()
        shop = TextLine.oneLine(Self.text(object["shop"]), limit: PriceWatch.maxShopChars)
        source = LooseNumber.value(object["source"]).flatMap { value in
            guard value.isFinite, value >= 1,
                  let index = Int(exactly: value.rounded(.towardZero)) else { return nil }
            return index
        }
        product = TextLine.oneLine(Self.text(object["product"]), limit: PriceWatch.maxTermChars)
    }

    private static func text(_ raw: Any?) -> String {
        guard let raw else { return "" }
        if let value = raw as? String { return value.trimmed }
        return String(describing: raw).trimmed
    }
}

struct PriceWatchOffer: Equatable, Sendable {
    var price: Double
    var currency: String
    var shop: String
    var url: String?
    var product: String

    #if DEBUG
    init(price: Double, currency: String = "", shop: String = "", url: String? = nil,
         product: String = "") {
        self.price = price
        self.currency = currency
        self.shop = shop
        self.url = url
        self.product = product
    }
    #endif

    init(report: PriceWatchReport, hits: [WebHit]) {
        let linked: WebHit? = report.source.flatMap { index -> WebHit? in
            guard index >= 1, hits.indices.contains(index - 1) else { return nil }
            return hits[index - 1]
        }
        price = report.price
        currency = report.currency
        shop = report.shop.isEmpty ? (linked?.domain ?? "") : report.shop
        url = linked?.url
        product = report.product
    }

    var traceLine: String {
        var parts = [String(format: "%.2f", price)]
        if !currency.isEmpty { parts.append(currency) }
        if !shop.isEmpty { parts.append(shop) }
        if url != nil { parts.append("quelle") }
        if !product.isEmpty { parts.append(TextLine.oneLine(product, limit: 50)) }
        return parts.joined(separator: " · ")
    }
}
