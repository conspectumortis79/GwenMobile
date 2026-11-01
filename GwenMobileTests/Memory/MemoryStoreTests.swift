@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class MemoryStoreTests: GwenTestCase {
    private func makeStore() -> (MemoryStore, StoragePaths) {
        let paths = temporaryPaths("gwen-memory")
        return (MemoryStore(paths: paths), paths)
    }

    private func require(_ result: (entry: MemoryEntry, merged: Bool)?) throws
        -> (entry: MemoryEntry, merged: Bool) {
        try XCTUnwrap(result)
    }

    func testAnEntryIsStoredOnDiskAndComesBack() async {
        let (store, paths) = makeStore()
        await store.add(text: "Ich esse kein Fleisch", category: .likes, source: .explicit)
        let reopened = MemoryStore(paths: paths)
        let entries = await reopened.all()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.text, "Ich esse kein Fleisch")
        XCTAssertEqual(entries.first?.category, .likes)
    }

    func testReplaceUpdatesTheSameEntryInsteadOfMakingADuplicate() async throws {
        let (store, _) = makeStore()
        let first = try require(await store.add(text: "Ich esse kein Fleisch", category: .likes,
                                                source: .explicit))
        let second = try require(await store.add(text: "Ich esse kein Fleisch, aber Fisch", category: .likes,
                                                 source: .explicit, replaceKey: first.entry.shortKey))
        XCTAssertTrue(second.merged)
        XCTAssertEqual(second.entry.id, first.entry.id)
        let count = await store.count()
        XCTAssertEqual(count, 1)
        XCTAssertEqual(second.entry.text, "Ich esse kein Fleisch, aber Fisch")
    }

    func testReplacingWithoutANewDateKeepsTheDueDate() async throws {
        let (store, _) = makeStore()
        let anchor = Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 12)) ?? Date()
        let first = try require(await store.add(text: "Zahnarzt", category: .health,
                                                source: .explicit, date: anchor, intervalMonths: 6,
                                                remind: true))
        let due = try XCTUnwrap(first.entry.dueDate)
        let replaced = try require(await store.add(text: "Zahnarzt Dr. Meier", category: .health,
                                                  source: .explicit, replaceKey: first.entry.shortKey))
        XCTAssertTrue(replaced.merged)
        XCTAssertEqual(replaced.entry.dueDate, due)
        XCTAssertTrue(replaced.entry.remind)
    }

    func testReplacingWithANewDateMovesTheDueDate() async throws {
        let (store, _) = makeStore()
        let firstDate = Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 12)) ?? Date()
        let secondDate = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 12)) ?? Date()
        let first = try require(await store.add(text: "Zahnarzt", category: .health,
                                                source: .explicit, date: firstDate, intervalMonths: 6))
        let oldDue = try XCTUnwrap(first.entry.dueDate)
        let replaced = try require(await store.add(text: "Zahnarzt Dr. Meier", category: .health,
                                                  source: .explicit, date: secondDate, intervalMonths: 6,
                                                  replaceKey: first.entry.shortKey))
        let expected = try XCTUnwrap(MemoryStore.dueDate(anchor: secondDate, intervalMonths: 6))
        XCTAssertTrue(replaced.merged)
        XCTAssertEqual(replaced.entry.dueDate, expected)
        XCTAssertNotEqual(replaced.entry.dueDate, oldDue)
    }

    func testANewVisitWithoutTheIntervalRollsTheDueDateForward() async throws {
        let (store, _) = makeStore()
        let firstDate = Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 12)) ?? Date()
        let visit = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 20)) ?? Date()
        let first = try require(await store.add(text: "Zahnarzt", category: .health, source: .explicit,
                                                date: firstDate, intervalMonths: 6, remind: true))
        let replaced = try require(await store.add(text: "Zahnarzt heute", category: .health,
                                                  source: .explicit, date: visit,
                                                  replaceKey: first.entry.shortKey))
        XCTAssertEqual(replaced.entry.anchor, visit)
        XCTAssertEqual(replaced.entry.intervalMonths, 6)
        XCTAssertEqual(replaced.entry.dueDate, MemoryStore.dueDate(anchor: visit, intervalMonths: 6))
        XCTAssertTrue(replaced.entry.remind)
        XCTAssertFalse(replaced.entry.notified)
    }

    func testANewIntervalAloneKeepsTheAnchor() async throws {
        let (store, _) = makeStore()
        let anchor = Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 12)) ?? Date()
        let first = try require(await store.add(text: "Zahnarzt", category: .health, source: .explicit,
                                                date: anchor, intervalMonths: 6))
        let replaced = try require(await store.add(text: "Zahnarzt jährlich", category: .health,
                                                  source: .explicit, intervalMonths: 12,
                                                  replaceKey: first.entry.shortKey))
        XCTAssertEqual(replaced.entry.anchor, anchor)
        XCTAssertEqual(replaced.entry.dueDate, MemoryStore.dueDate(anchor: anchor, intervalMonths: 12))
    }

    func testAnEntryStoredWithoutTheIntervalGetsItFromItsDates() throws {
        let anchor = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 31)) ?? Date()
        let monthly = try XCTUnwrap(MemoryStore.dueDate(anchor: anchor, intervalMonths: 1))
        let yearly = try XCTUnwrap(MemoryStore.dueDate(anchor: anchor, intervalMonths: 12))
        XCTAssertEqual(MemoryEntry.months(from: anchor, to: monthly), 1)
        XCTAssertEqual(MemoryEntry.months(from: anchor, to: yearly), 12)
        XCTAssertNil(MemoryEntry.months(from: nil, to: yearly))
        XCTAssertNil(MemoryEntry.months(from: anchor, to: nil))
        let stored = MemoryEntry(text: "Zahnarzt", category: .health, anchor: anchor, dueDate: yearly)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(stored))
            as? [String: Any])
        object["intervalMonths"] = nil
        let decoded = try JSONDecoder().decode(MemoryEntry.self,
                                               from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.intervalMonths, 12)
    }

    func testAnAcceptedSuggestionUpdatesTheEntryItNames() async throws {
        let (store, _) = makeStore()
        let first = try require(await store.add(text: "Ich mag Jazz", category: .likes, source: .explicit))
        let suggestion = MemorySuggestion(text: "Ich mag Jazz und Blues", category: .likes,
                                          replaceKey: first.entry.shortKey)
        let accepted = try require(await store.add(suggestion: suggestion))
        XCTAssertTrue(accepted.merged)
        XCTAssertEqual(accepted.entry.id, first.entry.id)
        let count = await store.count()
        XCTAssertEqual(count, 1)
    }

    func testSuggestionsAreOnlyOfferedWhileTheMemoryIsOn() {
        var settings = MemorySettings()
        XCTAssertTrue(settings.offersSuggestions)
        settings.suggestions = false
        XCTAssertFalse(settings.offersSuggestions)
        settings.suggestions = true
        settings.enabled = false
        XCTAssertFalse(settings.offersSuggestions)
    }

    func testDateAndIntervalProduceADueDate() async throws {
        let (store, _) = makeStore()
        let anchor = Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 12)) ?? Date()
        let result = try require(await store.add(text: "Ich war beim Zahnarzt", category: .health,
                                                 source: .explicit, date: anchor, intervalMonths: 6))
        let due = try XCTUnwrap(result.entry.dueDate)
        let parts = Calendar.current.dateComponents([.year, .month], from: due)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 11)
    }

    func testOnlyConfirmedRemindersBecomeDue() async throws {
        let (store, _) = makeStore()
        let anchor = Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 12)) ?? Date()
        let result = try require(await store.add(text: "Ich war beim Zahnarzt", category: .health,
                                                 source: .explicit, date: anchor, intervalMonths: 6))
        let after = (result.entry.dueDate ?? Date()).addingTimeInterval(86400)
        var due = await store.dueReminders(now: after)
        XCTAssertTrue(due.isEmpty)
        await store.setReminder(key: result.entry.shortKey, remind: true)
        due = await store.dueReminders(now: after)
        XCTAssertEqual(due.count, 1)
        await store.markNotified(key: result.entry.shortKey)
        due = await store.dueReminders(now: after)
        XCTAssertTrue(due.isEmpty)
    }

    func testTheDueLineNeverReadsZeroDaysWhenHoursRemain() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func entry(in seconds: TimeInterval) -> MemoryEntry {
            MemoryEntry(text: "Zahnarzt", category: .health, dueDate: now.addingTimeInterval(seconds))
        }
        XCTAssertEqual(MemoryStore.dueText(entry(in: -60), now: now), L.t("memory_due_now"))
        XCTAssertEqual(MemoryStore.dueText(entry(in: 30 * 60), now: now), L.t("memory_due_hour"))
        XCTAssertEqual(MemoryStore.dueText(entry(in: 3600), now: now), L.t("memory_due_hour"))
        XCTAssertEqual(MemoryStore.dueText(entry(in: 5 * 3600), now: now),
                       L.fmt("memory_due_hours", "5"))
        XCTAssertEqual(MemoryStore.dueText(entry(in: 20 * 3600), now: now),
                       L.fmt("memory_due_hours", "20"))
        XCTAssertEqual(MemoryStore.dueText(entry(in: 25 * 3600), now: now),
                       L.fmt("memory_due_days", "1"))
        XCTAssertEqual(MemoryStore.dueText(entry(in: 40 * 86400), now: now),
                       L.fmt("memory_due_days", "40"))
        XCTAssertEqual(MemoryStore.dueText(entry(in: 60 * 86400), now: now),
                       L.fmt("memory_due_months", "2"))
    }

    func testTheBlockNamesOnlyTheChosenEntries() async throws {
        let (store, _) = makeStore()
        let milk = try require(await store.add(text: "Ich mag keine Milch", category: .likes,
                                               source: .explicit))
        await store.add(text: "Ich mag keinen Spinat", category: .likes, source: .explicit)
        let block = await store.block(keys: [milk.entry.shortKey])
        XCTAssertTrue(block.contains("## PERSONAL MEMORY"))
        XCTAssertTrue(block.contains("Ich mag keine Milch"))
        XCTAssertFalse(block.contains("Spinat"))
    }

    func testTheCatalogCarriesStableKeys() async throws {
        let (store, _) = makeStore()
        let result = try require(await store.add(text: "Ich esse kein Fleisch", category: .likes,
                                                 source: .explicit))
        let catalog = await store.catalog()
        XCTAssertTrue(catalog.contains("[#" + result.entry.shortKey + "]"))
        XCTAssertTrue(catalog.contains("Ich esse kein Fleisch"))
        let resolved = await store.entry(key: "#" + result.entry.shortKey.uppercased())
        XCTAssertEqual(resolved?.id, result.entry.id)
    }

    func testUsedEntriesCountUp() async throws {
        let (store, _) = makeStore()
        let result = try require(await store.add(text: "Ich esse kein Fleisch", category: .likes,
                                                 source: .explicit))
        await store.markUsed(keys: [result.entry.shortKey])
        let entries = await store.all()
        XCTAssertEqual(entries.first?.useCount, 1)
        XCTAssertNotNil(entries.first?.lastUsedAt)
    }

    func testRetentionPrunesOldEntriesButKeepsPinnedAndRemindedOnes() async throws {
        let (store, _) = makeStore()
        let oldDate = Calendar.current.date(byAdding: .month, value: -14, to: Date()) ?? Date()
        await store.add(text: "Alte Vorliebe", category: .likes, source: .said, now: oldDate)
        let pinned = try require(await store.add(text: "Wichtige Vorliebe", category: .likes,
                                                 source: .said, now: oldDate))
        await store.setPinned(key: pinned.entry.shortKey, pinned: true)
        let reminded = try require(await store.add(text: "Frist-Vorliebe", category: .plans,
                                                   source: .said, date: oldDate, intervalMonths: 24,
                                                   now: oldDate))
        await store.setReminder(key: reminded.entry.shortKey, remind: true)
        await store.prune(retention: .twelveMonths)
        let texts = await store.all().map(\.text)
        XCTAssertFalse(texts.contains("Alte Vorliebe"))
        XCTAssertTrue(texts.contains("Wichtige Vorliebe"))
        XCTAssertTrue(texts.contains("Frist-Vorliebe"))
    }

    func testDeleteReturnsTheIndexAndRestoreKeepsTheOrder() async throws {
        let (store, paths) = makeStore()
        let first = try require(await store.add(text: "Erster Eintrag", category: .person,
                                                source: .manual))
        let second = try require(await store.add(text: "Zweiter Eintrag", category: .likes,
                                                 source: .manual))
        let third = try require(await store.add(text: "Dritter Eintrag", category: .work,
                                                source: .manual))
        let index = await store.delete(key: second.entry.shortKey)
        XCTAssertEqual(index, 1)
        let missing = await store.delete(key: second.entry.shortKey)
        XCTAssertNil(missing)
        let afterDelete = await store.all()
        XCTAssertEqual(afterDelete.map(\.id), [third.entry.id, first.entry.id])
        let restored = await store.restore(second.entry, at: 1)
        XCTAssertTrue(restored)
        let duplicate = await store.restore(second.entry, at: 1)
        XCTAssertFalse(duplicate)
        let all = await store.all()
        XCTAssertEqual(all.map(\.id), [third.entry.id, second.entry.id, first.entry.id])
        let reopened = MemoryStore(paths: paths)
        let persisted = await reopened.all()
        XCTAssertEqual(persisted.map(\.id), all.map(\.id))
    }

    func testRestoreClampsTheIndexAndIgnoresDuplicates() async throws {
        let (store, _) = makeStore()
        let entry = try require(await store.add(text: "Ein Eintrag", category: .plans,
                                                source: .manual))
        let firstIndex = await store.delete(key: entry.entry.shortKey)
        XCTAssertEqual(firstIndex, 0)
        let appended = await store.restore(entry.entry, at: 20)
        XCTAssertTrue(appended)
        let duplicate = await store.restore(entry.entry, at: 0)
        XCTAssertFalse(duplicate)
        let secondIndex = await store.delete(key: entry.entry.shortKey)
        XCTAssertEqual(secondIndex, 0)
        let prepended = await store.restore(entry.entry, at: -4)
        XCTAssertTrue(prepended)
        let count = await store.count()
        XCTAssertEqual(count, 1)
    }

    func testCleaningKeepsTextTidy() {
        XCTAssertEqual(MemoryStore.cleanText("  ich mag   hafermilch!  "), "Ich mag hafermilch")
    }

    func testExportCarriesTheEntries() async throws {
        let (store, _) = makeStore()
        await store.add(text: "Ich esse kein Fleisch", category: .likes, source: .explicit)
        let data = await store.exportData()
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let entries = object?["entries"] as? [[String: Any]]
        XCTAssertEqual(entries?.count, 1)
    }

    func testAFailedSaveIsReported() async throws {
        let (store, paths) = makeStore()
        let received = LockedValue<String?>(nil)
        await store.reportFailures { received.set($0) }
        try makeSupportUnwritable(paths)
        defer { restoreSupport(paths) }
        await store.add(text: "Erster Eintrag", category: .likes, source: .explicit)
        XCTAssertTrue(received.current?.contains("speichern") ?? false, received.current ?? "keine Meldung")
    }
}
