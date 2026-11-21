import GwenMobileKit
import Foundation

actor PriceWatchStore: FailureReporting {
    private struct FileSignature: Equatable {
        let stamp: Date?
        let size: Int?
        let version: Int
    }

    private struct Snapshot {
        let signature: FileSignature
        let watches: [PriceWatch]
    }

    static let catalogLimit = 20
    static let catalogTextLimit = 70

    private static let fileLock = NSLock()
    private static let writeVersion = LockedValue(0)

    private let paths: StoragePaths
    let failures = FailureReporter(label: "PREISWECKER")
    private var snapshot: Snapshot?

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
        return matchIndex(in: watches, key: key, terms: terms).map { watches[$0] }
    }

    private func matchIndex(in watches: [PriceWatch], key: String?, terms: [String]) -> Int? {
        if let key, !key.isEmpty {
            return watches.firstIndex { $0.matches(key: key, terms: []) }
        }
        return watches.firstIndex { $0.matches(key: nil, terms: terms) }
    }

    @discardableResult
    func create(terms wanted: [String], goal: Double, intervalHours: Int?, currencyCode: String?,
                regionCode: String?, wording: String = "", now: Date = Date())
        -> (watch: PriceWatch, created: Bool)? {
        let terms = PriceWatch.cleanTerms(wanted)
        let request = PriceWatch.cleanWording(wording)
        guard !terms.isEmpty, goal > 0, goal <= PriceWatch.maximumGoal else { return nil }
        return synchronized {
            var watches = loadUnlocked()
            let interval = PriceWatch.clampInterval(intervalHours)
            if let index = watches.firstIndex(where: { PriceWatch.sameProduct($0.terms, terms) }) {
                applyUpdate(to: &watches[index], goal: goal, intervalHours: intervalHours, now: now)
                watches[index].paused = false
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
    func update(key: String?, terms: [String], goal: Double?, intervalHours: Int?,
                now: Date = Date()) -> PriceWatch? {
        synchronized {
            var watches = loadUnlocked()
            guard let index = matchIndex(in: watches, key: key, terms: terms) else { return nil }
            applyUpdate(to: &watches[index], goal: goal, intervalHours: intervalHours, now: now)
            save(watches)
            return watches[index]
        }
    }

    private func applyUpdate(to watch: inout PriceWatch, goal: Double?, intervalHours: Int?, now: Date) {
        if let goal, goal > 0, goal <= PriceWatch.maximumGoal, watch.goal != goal {
            watch.goal = goal
            watch.notifiedPrice = nil
            if !watch.reached { watch.hitAt = nil }
        }
        if let intervalHours { watch.intervalHours = PriceWatch.clampInterval(intervalHours) }
        watch.updatedAt = now
    }

    @discardableResult
    func delete(key: String?, terms: [String]) -> PriceWatch? {
        synchronized {
            var watches = loadUnlocked()
            guard let index = matchIndex(in: watches, key: key, terms: terms) else { return nil }
            let removed = watches.remove(at: index)
            save(watches)
            return removed
        }
    }

    @discardableResult
    func restore(_ watch: PriceWatch) -> Bool {
        synchronized {
            var watches = loadUnlocked()
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
            watches[index].lastShop = offer.shop.isEmpty ? nil : offer.shop
            watches[index].lastURL = offer.url.flatMap { $0.isEmpty ? nil : $0 }
            watches[index].lastProduct = offer.product.isEmpty ? nil : offer.product
            if watches[index].accepts(offer), offer.price <= watches[index].goal {
                if watches[index].hitAt == nil { watches[index].hitAt = now }
            } else {
                watches[index].hitAt = nil
                watches[index].notifiedPrice = nil
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
        Self.fileLock.lock()
        defer { Self.fileLock.unlock() }
        return loadUnlocked()
    }

    private func loadUnlocked() -> [PriceWatch] {
        let signature = Self.fileSignature(of: paths.watches)
        if let snapshot, snapshot.signature == signature { return snapshot.watches }
        let watches = readFromDisk()
        snapshot = Snapshot(signature: signature, watches: watches)
        return watches
    }

    private func mutate(_ body: (inout [PriceWatch]) -> Bool) {
        synchronized {
            var watches = loadUnlocked()
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
        let decoded = StorageJSON.read([FailableDecodable<PriceWatch>].self, from: paths.watches,
                                       failures: failures) ?? []
        let values = decoded.compactMap(\.value)
        if values.count != decoded.count {
            flowLog.error("PREISWECKER eintrag unlesbar anzahl=\(decoded.count - values.count, privacy: .public)")
        }
        return values.filter { $0.goal > 0 && !PriceWatch.cleanTerms($0.terms).isEmpty }
    }

    private func save(_ watches: [PriceWatch]) {
        guard StorageJSON.write(watches, to: paths.watches, support: paths.support,
                                failures: failures) else { return }
        Self.writeVersion.mutate { $0 += 1 }
        snapshot = Snapshot(signature: Self.fileSignature(of: paths.watches), watches: watches)
    }

    private static func fileSignature(of url: URL) -> FileSignature {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return FileSignature(stamp: attrs?[.modificationDate] as? Date,
                             size: (attrs?[.size] as? NSNumber)?.intValue,
                             version: writeVersion.current)
    }
}
