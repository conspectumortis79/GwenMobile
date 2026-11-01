import GwenMobileKit
import Foundation

actor MemoryStore {
    static let catalogLimit = 40
    static let catalogTextLimit = 140
    static let maxBlockCharacters = 900

    private let paths: StoragePaths
    private var entries: [MemoryEntry] = []
    private var isLoaded = false
    private let failures = FailureReporter(label: "GEDÄCHTNIS")

    func reportFailures(_ handler: @escaping @Sendable (String) -> Void) {
        failures.report(to: handler)
    }

    init(paths: StoragePaths = StoragePaths()) {
        self.paths = paths
    }

    private func loadIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true
        guard let decoded = StorageJSON.read([MemoryEntry].self, from: paths.memory,
                                             failures: failures) else { return }
        entries = decoded.filter { !Self.cleanText($0.text).isEmpty }
    }

    private func save() {
        StorageJSON.write(entries, to: paths.memory, support: paths.support, failures: failures)
    }

    func all() -> [MemoryEntry] {
        loadIfNeeded()
        return entries
    }

    func count() -> Int {
        loadIfNeeded()
        return entries.count
    }

    func entry(key: String?) -> MemoryEntry? {
        loadIfNeeded()
        guard let key else { return nil }
        let wanted = EntityKey.normalized(key)
        guard !wanted.isEmpty else { return nil }
        return entries.first { $0.shortKey == wanted || $0.id.uuidString.lowercased().hasPrefix(wanted) }
    }

    func entries(keys: [String]) -> [MemoryEntry] {
        loadIfNeeded()
        return keys.compactMap { entry(key: $0) }
    }

    @discardableResult
    func add(text: String, category: MemoryCategory, source: MemorySource,
             date: Date? = nil, intervalMonths: Int? = nil, replaceKey: String? = nil,
             remind: Bool = false, now: Date = Date()) -> (entry: MemoryEntry, merged: Bool)? {
        loadIfNeeded()
        let clean = Self.cleanText(text)
        guard !clean.isEmpty else { return nil }
        if let merged = mutate(key: replaceKey, { item in
            item.text = clean
            item.category = category
            item.sensitive = category.isSensitive
            item.updatedAt = now
            if date != nil || intervalMonths != nil {
                Self.apply(date: date, intervalMonths: intervalMonths, to: &item)
            }
            if remind {
                item.remind = true
                item.notified = false
            }
            return true
        }) {
            return (merged, true)
        }
        var entry = MemoryEntry(text: clean, category: category, source: source,
                                createdAt: now, updatedAt: now)
        Self.apply(date: date, intervalMonths: intervalMonths, to: &entry)
        entry.remind = remind
        entries.insert(entry, at: 0)
        save()
        return (entry, false)
    }

    @discardableResult
    func add(suggestion: MemorySuggestion, source: MemorySource = .suggestion,
             now: Date = Date()) -> (entry: MemoryEntry, merged: Bool)? {
        add(text: suggestion.text, category: suggestion.category, source: source,
            date: suggestion.anchor, intervalMonths: suggestion.intervalMonths,
            replaceKey: suggestion.replaceKey, now: now)
    }

    func update(key: String, text: String, category: MemoryCategory, pinned: Bool, remind: Bool,
                now: Date = Date()) {
        mutate(key: key) { item in
            let clean = Self.cleanText(text)
            if !clean.isEmpty { item.text = clean }
            item.category = category
            item.pinned = pinned
            item.sensitive = category.isSensitive
            item.updatedAt = now
            if item.dueDate != nil {
                Self.applyReminder(remind, to: &item)
            }
            return true
        }
    }

    func setPinned(key: String, pinned: Bool) {
        mutate(key: key) { item in
            item.pinned = pinned
            item.updatedAt = Date()
            return true
        }
    }

    @discardableResult
    func delete(key: String) -> Int? {
        loadIfNeeded()
        guard let existing = entry(key: key),
              let index = entries.firstIndex(where: { $0.id == existing.id }) else { return nil }
        entries.remove(at: index)
        save()
        return index
    }

    @discardableResult
    func restore(_ entry: MemoryEntry, at index: Int) -> Bool {
        loadIfNeeded()
        guard !entries.contains(where: { $0.id == entry.id }) else { return false }
        entries.insert(entry, at: min(max(index, 0), entries.count))
        save()
        return true
    }

    func deleteAll() {
        loadIfNeeded()
        entries = []
        save()
    }

    private static func applyReminder(_ remind: Bool, to item: inout MemoryEntry) {
        guard item.dueDate != nil, remind != item.remind else { return }
        item.notified = false
        item.remind = remind
    }

    @discardableResult
    private func mutate(key: String?, _ body: (inout MemoryEntry) -> Bool) -> MemoryEntry? {
        loadIfNeeded()
        guard let existing = entry(key: key), let index = entries.firstIndex(where: { $0.id == existing.id }),
              body(&entries[index]) else { return nil }
        save()
        return entries[index]
    }

    #if DEBUG
    func setReminder(key: String, remind: Bool) {
        mutate(key: key) { item in
            guard item.dueDate != nil else { return false }
            Self.applyReminder(remind, to: &item)
            return true
        }
    }
    #endif

    func markUsed(keys: [String], at date: Date = Date()) {
        loadIfNeeded()
        let wanted = Set(entries(keys: keys).map(\.id))
        guard !wanted.isEmpty else { return }
        for index in entries.indices where wanted.contains(entries[index].id) {
            if entries[index].useCount < Int.max {
                entries[index].useCount += 1
            }
            entries[index].lastUsedAt = date
        }
        save()
    }

    func dueReminders(now: Date = Date()) -> [MemoryEntry] {
        loadIfNeeded()
        return entries.filter { entry in
            entry.remind && !entry.notified && (entry.dueDate.map { $0 <= now } ?? false)
        }
    }

    func markNotified(key: String) {
        mutate(key: key) { item in
            item.notified = true
            return true
        }
    }

    func prune(retention: MemoryRetention, now: Date = Date()) {
        loadIfNeeded()
        guard let months = retention.months,
              let cutoff = Calendar.current.date(byAdding: .month, value: -months, to: now) else { return }
        let before = entries.count
        entries.removeAll { !$0.pinned && !$0.remind && $0.createdAt < cutoff }
        guard entries.count != before else { return }
        save()
    }

    func exportData(now: Date = Date()) -> Data {
        loadIfNeeded()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        struct Export: Encodable {
            var exported: Date
            var entries: [MemoryEntry]
        }
        return (try? encoder.encode(Export(exported: now, entries: entries))) ?? Data()
    }

    func catalog() -> String {
        loadIfNeeded()
        guard !entries.isEmpty else { return "" }
        let ordered = entries.sorted {
            if $0.pinned != $1.pinned { return $0.pinned }
            let left = $0.lastUsedAt ?? $0.updatedAt
            let right = $1.lastUsedAt ?? $1.updatedAt
            return left > right
        }
        return ordered.prefix(Self.catalogLimit).map { entry in
            Self.catalogLine(entry)
        }.joined(separator: "\n")
    }

    func block(keys: [String]) -> String {
        let used = entries(keys: keys)
        guard !used.isEmpty else { return "" }
        var block = PromptLibrary.text("memory_block_head") + "\n"
        for entry in used {
            let line = "- " + Self.memoryLine(entry) + "\n"
            guard block.count + line.count <= Self.maxBlockCharacters else { break }
            block += line
        }
        return block
    }

    nonisolated static func cleanText(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " .!?,;:"))
        guard !text.isEmpty else { return "" }
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    nonisolated static func dueText(_ entry: MemoryEntry, now: Date = Date()) -> String? {
        guard let due = entry.dueDate else { return nil }
        let seconds = due.timeIntervalSince(now)
        if seconds <= 0 { return L.t("memory_due_now") }
        if seconds < 86400 {
            let hours = max(1, Int((seconds / 3600).rounded(.up)))
            return hours == 1 ? L.t("memory_due_hour") : L.fmt("memory_due_hours", String(hours))
        }
        let days = Int((seconds / 86400).rounded())
        if days < 45 { return L.fmt("memory_due_days", String(days)) }
        let months = Int((Double(days) / 30.44).rounded())
        if months < 24 { return L.fmt("memory_due_months", String(months)) }
        return L.fmt("memory_due_years", String(Int((Double(months) / 12).rounded())))
    }

    nonisolated static func dueDate(anchor: Date, intervalMonths: Int) -> Date? {
        Calendar.current.date(byAdding: .month, value: intervalMonths, to: anchor)
    }

    private static func apply(date: Date?, intervalMonths: Int?, to entry: inout MemoryEntry) {
        let anchor = date ?? entry.anchor
        let interval = intervalMonths ?? entry.intervalMonths
        entry.anchor = anchor
        entry.intervalMonths = interval
        entry.dueDate = anchor.flatMap { start in
            interval.flatMap { dueDate(anchor: start, intervalMonths: $0) }
        }
        entry.notified = false
    }

    private static func catalogLine(_ entry: MemoryEntry) -> String {
        var notes = [entry.category.promptName]
        if entry.pinned { notes.append("pinned") }
        if let anchor = entry.anchor { notes.append("anchored " + Formatters.stamp(anchor)) }
        if let due = entry.dueDate { notes.append("due " + Formatters.stamp(due)) }
        if entry.sensitive { notes.append("sensitive") }
        return CatalogLine.entry(key: entry.shortKey, text: entry.text, limit: catalogTextLimit, notes: notes)
    }

    private static func memoryLine(_ entry: MemoryEntry) -> String {
        var notes = [entry.category.promptName]
        if let anchor = entry.anchor { notes.append("anchored on " + Formatters.stamp(anchor)) }
        if let due = entry.dueDate { notes.append("next due about " + Formatters.stamp(due)) }
        if entry.pinned { notes.append("pinned") }
        if entry.sensitive { notes.append("sensitive, the user shared it explicitly") }
        return entry.text + " (" + notes.joined(separator: ", ") + ")"
    }
}
