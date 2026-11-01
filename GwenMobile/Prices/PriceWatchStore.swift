import GwenMobileKit
import Foundation

actor PriceWatchStore {
    private struct Snapshot {
        let stamp: Date?
        let watches: [PriceWatch]
    }

    static let catalogLimit = 20
    static let catalogTextLimit = 70

    private static let fileLock = NSLock()

    private let paths: StoragePaths
    private let failures = FailureReporter(label: "PREISWECKER")
    private var snapshot: Snapshot?

    func reportFailures(_ handler: @escaping @Sendable (String) -> Void) {
        failures.report(to: handler)
    }

    init(paths: StoragePaths = StoragePaths()) {
        self.paths = paths
    }

    func all() -> [PriceWatch] {
        load().sorted { $0.updatedAt > $1.updatedAt }
    }

    func count() -> Int {
        load().count
    }

    func active() -> [PriceWatch] {
        all().filter { !$0.paused }
    }

    func watch(id: UUID) -> PriceWatch? {
        load().first { $0.id == id }
    }

    func match(key: String?, terms: [String]) -> PriceWatch? {
        let watches = load()
        if let key, !key.isEmpty, let found = watches.first(where: { $0.matches(key: key, terms: []) }) {
            return found
        }
        return watches.first { $0.matches(key: nil, terms: terms) }
    }

    @discardableResult
    func create(terms wanted: [String], goal: Double, intervalHours: Int?, currencyCode: String?,
                regionCode: String?, wording: String = "", now: Date = Date())
        -> (watch: PriceWatch, created: Bool)? {
        let terms = PriceWatch.cleanTerms(wanted)
        let request = PriceWatch.cleanWording(wording)
        guard !terms.isEmpty, goal > 0, goal <= PriceWatch.maximumGoal else { return nil }
        return synchronized {
            var watches = load()
            let interval = PriceWatch.clampInterval(intervalHours)
            if let index = watches.firstIndex(where: { $0.matches(key: nil, terms: terms) }) {
                watches[index].goal = goal
                watches[index].intervalHours = interval
                watches[index].paused = false
                watches[index].updatedAt = now
                if let currencyCode, !currencyCode.isEmpty { watches[index].currencyCode = currencyCode }
                if let regionCode, !regionCode.isEmpty { watches[index].regionCode = regionCode }
                if !request.isEmpty { watches[index].wording = request }
                watches[index].terms = PriceWatch.cleanTerms(terms + watches[index].terms)
                save(watches)
                return (watches[index], false)
            }
            let watch = PriceWatch(terms: terms, goal: goal, wording: request, currencyCode: currencyCode,
                                   regionCode: regionCode, intervalHours: interval,
                                   createdAt: now, updatedAt: now)
            watches.insert(watch, at: 0)
            save(watches)
            return (watch, true)
        }
    }

    @discardableResult
    func update(id: UUID, goal: Double?, intervalHours: Int?, now: Date = Date()) -> PriceWatch? {
        synchronized {
            var watches = load()
            guard let index = watches.firstIndex(where: { $0.id == id }) else { return nil }
            if let goal, goal > 0, goal <= PriceWatch.maximumGoal { watches[index].goal = goal }
            if let intervalHours { watches[index].intervalHours = PriceWatch.clampInterval(intervalHours) }
            watches[index].updatedAt = now
            save(watches)
            return watches[index]
        }
    }

    @discardableResult
    func update(key: String?, terms: [String], goal: Double?, intervalHours: Int?,
                now: Date = Date()) -> PriceWatch? {
        guard let found = match(key: key, terms: terms) else { return nil }
        return update(id: found.id, goal: goal, intervalHours: intervalHours, now: now)
    }

    @discardableResult
    func delete(key: String?, terms: [String]) -> PriceWatch? {
        synchronized {
            guard let found = match(key: key, terms: terms) else { return nil }
            var watches = load()
            watches.removeAll { $0.id == found.id }
            save(watches)
            return found
        }
    }

    @discardableResult
    func restore(_ watch: PriceWatch) -> Bool {
        synchronized {
            var watches = load()
            guard !watches.contains(where: { $0.id == watch.id }) else { return false }
            watches.append(watch)
            save(watches)
            return true
        }
    }

    func setPaused(id: UUID, paused: Bool, now: Date = Date()) {
        mutate { watches in
            guard let index = watches.firstIndex(where: { $0.id == id }) else { return false }
            watches[index].paused = paused
            watches[index].updatedAt = now
            return true
        }
    }

    func record(id: UUID, offer: PriceWatchOffer?, fallbackCurrency: String?, now: Date = Date()) {
        mutate { watches in
            guard let index = watches.firstIndex(where: { $0.id == id }) else { return false }
            watches[index].lastCheckedAt = now
            watches[index].updatedAt = now
            guard let offer else { return true }
            watches[index].lastPrice = offer.price
            watches[index].lastCurrency = offer.currency.isEmpty ? fallbackCurrency : offer.currency
            if !offer.shop.isEmpty { watches[index].lastShop = offer.shop }
            if let url = offer.url, !url.isEmpty { watches[index].lastURL = url }
            watches[index].lastProduct = offer.product.isEmpty ? nil : offer.product
            if watches[index].accepts(offer), offer.price <= watches[index].goal {
                if watches[index].hitAt == nil { watches[index].hitAt = now }
            } else {
                watches[index].hitAt = nil
            }
            return true
        }
    }

    func markNotified(id: UUID, price: Double) {
        mutate { watches in
            guard let index = watches.firstIndex(where: { $0.id == id }) else { return false }
            watches[index].notifiedPrice = price
            return true
        }
    }
    func due(now: Date = Date()) -> [PriceWatch] {
        active().filter { $0.isDue(now: now) }
    }

    func nextDueDate() -> Date? {
        active().map(\.nextDue).min()
    }

    func catalog() -> String {
        let watches = all()
        guard !watches.isEmpty else { return "" }
        return watches.prefix(Self.catalogLimit).map { watch in
            var notes = ["goal " + Formatters.price(watch.goal, currency: watch.currencyCode),
                         watch.status.rawValue]
            if let product = watch.lastProduct, !product.isEmpty {
                notes.append("offer " + TextLine.oneLine(product, limit: Self.catalogTextLimit))
            }
            if let price = watch.lastPrice {
                let seen = Formatters.price(price, currency: watch.lastCurrency ?? watch.currencyCode)
                if let shop = watch.lastShop, !shop.isEmpty {
                    notes.append("last seen " + seen + " at " + shop)
                } else {
                    notes.append("last seen " + seen)
                }
            }
            if let checked = watch.lastCheckedAt {
                notes.append("checked " + Formatters.stamp(checked))
            }
            return CatalogLine.entry(key: watch.shortKey, text: watch.product, limit: Self.catalogTextLimit,
                                     notes: notes)
        }.joined(separator: "\n")
    }

    private func load() -> [PriceWatch] {
        let stamp = Self.modificationDate(of: paths.watches)
        if let snapshot, snapshot.stamp == stamp { return snapshot.watches }
        let watches = readFromDisk()
        snapshot = Snapshot(stamp: stamp, watches: watches)
        return watches
    }

    private func mutate(_ body: (inout [PriceWatch]) -> Bool) {
        synchronized {
            var watches = load()
            guard body(&watches) else { return }
            save(watches)
        }
    }

    private func synchronized<Outcome>(_ body: () -> Outcome) -> Outcome {
        Self.fileLock.lock()
        defer { Self.fileLock.unlock() }
        snapshot = nil
        return body()
    }

    private func readFromDisk() -> [PriceWatch] {
        let decoded = StorageJSON.read([PriceWatch].self, from: paths.watches,
                                       failures: failures) ?? []
        return decoded.filter { $0.goal > 0 && !PriceWatch.cleanTerms($0.terms).isEmpty }
    }

    private func save(_ watches: [PriceWatch]) {
        guard StorageJSON.write(watches, to: paths.watches, support: paths.support,
                                failures: failures) else { return }
        snapshot = Snapshot(stamp: Self.modificationDate(of: paths.watches), watches: watches)
    }

    private static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
