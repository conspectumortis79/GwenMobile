@testable import GwenMobileFeatureCore
import UserNotifications
import XCTest
import GwenMobileKit

@MainActor
final class MemoryGapCoverageTests: GwenTestCase {
    private func makeStore(_ prefix: String = "memory-gap") -> MemoryStore {
        MemoryStore(paths: temporaryPaths(prefix))
    }

    private func entry(_ text: String = "mag Tee", category: MemoryCategory = .likes,
                       pinned: Bool = false, due: Date? = nil, remind: Bool = false,
                       notified: Bool = false) -> MemoryEntry {
        MemoryEntry(text: text, category: category, pinned: pinned, dueDate: due,
                    remind: remind, notified: notified)
    }

    func testEveryCategoryAndRetentionName() {
        for category in MemoryCategory.allCases {
            XCTAssertFalse(category.promptName.isEmpty, "\(category)")
            XCTAssertFalse(category.symbol.isEmpty, "\(category)")
        }
        XCTAssertTrue(MemoryCategory.health.isSensitive)
        XCTAssertFalse(MemoryCategory.likes.isSensitive)
        for retention in MemoryRetention.allCases {
            XCTAssertFalse(retention.id.isEmpty, "\(retention)")
            XCTAssertFalse(retention.labelKey.isEmpty, "\(retention)")
        }
        XCTAssertNil(MemoryRetention.forever.months)
        XCTAssertEqual(MemoryRetention.twelveMonths.months, 12)
        XCTAssertEqual(MemoryRetention.threeMonths.months, 3)
    }

    func testTheLooseDecodingOfAnEntry() throws {
        let decoded = try JSONDecoder().decode(MemoryEntry.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded.text, "")
        XCTAssertEqual(decoded.category, .person)
        XCTAssertEqual(decoded.source, .said)
        XCTAssertEqual(decoded.useCount, 0)
        XCTAssertFalse(decoded.pinned)
        XCTAssertFalse(decoded.remind)
        XCTAssertFalse(decoded.notified)
        XCTAssertFalse(decoded.sensitive)
        XCTAssertEqual(decoded.updatedAt, decoded.createdAt)
        XCTAssertEqual(decoded.shortKey.count, 8)
    }

    func testTheAnswerWords() throws {
        let due = Date().addingTimeInterval(3600)
        let merged = MemoryAnswers.saved(entry(due: due), merged: true)
        XCTAssertTrue(merged.contains(L.t("memory_saved_updated")))
        let fresh = MemoryAnswers.saved(entry(due: due), merged: false)
        XCTAssertTrue(fresh.contains(L.t("memory_saved")))
        XCTAssertTrue(fresh.contains("\u{201C}mag Tee\u{201D}"), fresh)
        XCTAssertTrue(MemoryAnswers.forgot(entry()).contains("\u{201C}mag Tee\u{201D}"))
        let dueText = try XCTUnwrap(MemoryStore.dueText(entry(due: due)))
        XCTAssertTrue(fresh.contains(L.fmt("memory_due_line", dueText)))
        XCTAssertTrue(MemoryAnswers.forgot(entry()).contains("mag Tee"))
        XCTAssertFalse(MemoryAnswers.forgetMissing().isEmpty)
        XCTAssertFalse(MemoryAnswers.off().isEmpty)
        XCTAssertEqual(MemoryAnswers.list([]), L.t("memory_list_empty"))
        let listed = MemoryAnswers.list([entry("fest", pinned: true), entry("normal")])
        XCTAssertTrue(listed.contains("fest"))
        XCTAssertTrue(listed.contains(L.t("memory_cat_likes")))
    }

    func testTheDueTextSpansEveryDistance() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertNil(MemoryStore.dueText(entry(), now: now))
        XCTAssertEqual(MemoryStore.dueText(entry(due: now.addingTimeInterval(-10)), now: now),
                       L.t("memory_due_now"))
        XCTAssertEqual(MemoryStore.dueText(entry(due: now.addingTimeInterval(3600)), now: now),
                       L.t("memory_due_hour"))
        XCTAssertEqual(MemoryStore.dueText(entry(due: now.addingTimeInterval(7200)), now: now),
                       L.fmt("memory_due_hours", "2"))
        XCTAssertEqual(MemoryStore.dueText(entry(due: now.addingTimeInterval(5 * 86400)), now: now),
                       L.fmt("memory_due_days", "5"))
        XCTAssertEqual(MemoryStore.dueText(entry(due: now.addingTimeInterval(60 * 86400)), now: now),
                       L.fmt("memory_due_months", "2"))
        XCTAssertEqual(MemoryStore.dueText(entry(due: now.addingTimeInterval(800 * 86400)), now: now),
                       L.fmt("memory_due_years", "2"))
    }

    func testTheStoreGuardsAndReminderPaths() async throws {
        let store = makeStore()
        let nilKey = await store.entry(key: nil)
        XCTAssertNil(nilKey)
        let hashKey = await store.entry(key: " # ")
        XCTAssertNil(hashKey)
        let emptyAdd = await store.add(text: "   ", category: .person, source: .explicit)
        XCTAssertNil(emptyAdd)
        let due = Date(timeIntervalSince1970: 1_800_000_000)
        let madeOption = await store.add(text: "Zahnarzt", category: .health,
                                         source: .explicit, date: due, intervalMonths: 1, remind: true)
        let made = try XCTUnwrap(madeOption)
        let key = made.entry.shortKey
        await store.update(key: key + "#", text: "  Zahnarzt neu  ", category: .work,
                           pinned: true, remind: false)
        await store.update(key: "gibtsnicht", text: "x", category: .person, pinned: false, remind: false)
        let updated = await store.entry(key: key)
        XCTAssertEqual(updated?.text, "Zahnarzt neu")
        XCTAssertEqual(updated?.pinned, true)
        await store.setPinned(key: "gibtsnicht", pinned: true)
        await store.setReminder(key: key, remind: true)
        await store.setReminder(key: "gibtsnicht", remind: true)
        let later = Date(timeIntervalSince1970: 1_900_000_000)
        let dueBefore = await store.dueReminders(now: later)
        XCTAssertEqual(dueBefore.count, 1)
        await store.markNotified(key: key)
        let dueAfter = await store.dueReminders(now: later)
        XCTAssertEqual(dueAfter.count, 0)
        await store.markNotified(key: "gibtsnicht")
        let exported = await store.exportData(now: later)
        XCTAssertFalse(exported.isEmpty)
        let catalog = await store.catalog()
        XCTAssertTrue(catalog.contains("Zahnarzt neu"))
        await store.delete(key: "gibtsnicht")
        await store.delete(key: key)
        let empty = await store.count()
        XCTAssertEqual(empty, 0)
        await store.deleteAll()
    }

    func testTheSuggestionAdoption() async {
        let store = makeStore("memory-gap-suggestion")
        let suggestion = MemorySuggestion(text: "mag Kaffee", category: .likes,
                                          anchor: Date(), intervalMonths: 12)
        _ = await store.add(suggestion: suggestion, source: .suggestion)
        let count = await store.count()
        XCTAssertEqual(count, 1)
        let entries = await store.all()
        XCTAssertEqual(entries.first?.category, .likes)
    }

    func testSmokeTheNotifierUsesTheSystemDefaults() async {
        _ = await MemoryNotifier.delivery.authorizationStatus()
        let request = UNNotificationRequest(identifier: "gwen.test.\(UUID().uuidString)",
                                            content: UNMutableNotificationContent(), trigger: nil)
        _ = try? await MemoryNotifier.delivery.deliver(request)
    }

    func testTheNotifierPreparesAndSends() async {
        let originalStatus = MemoryNotifier.delivery.authorizationStatus
        let originalDeliver = MemoryNotifier.delivery.deliverOverride
        defer {
            MemoryNotifier.delivery.authorizationStatus = originalStatus
            MemoryNotifier.delivery.deliverOverride = originalDeliver
        }
        MemoryNotifier.delivery.authorizationStatus = { .authorized }
        MemoryNotifier.delivery.deliverOverride = { _ in }
        MemoryNotifier.prepare()
        let sent = await MemoryNotifier.notify(entry())
        XCTAssertTrue(sent)
    }

    func testTheNotifierReportsDeniedAndFailedDeliveries() async {
        let originalStatus = MemoryNotifier.delivery.authorizationStatus
        let originalDeliver = MemoryNotifier.delivery.deliverOverride
        defer {
            MemoryNotifier.delivery.authorizationStatus = originalStatus
            MemoryNotifier.delivery.deliverOverride = originalDeliver
        }
        MemoryNotifier.delivery.authorizationStatus = { .denied }
        let denied = await MemoryNotifier.notify(entry())
        XCTAssertFalse(denied)
        MemoryNotifier.delivery.authorizationStatus = { .authorized }
        MemoryNotifier.delivery.deliverOverride = { _ in throw APIError(message: "kaputt") }
        let failed = await MemoryNotifier.notify(entry())
        XCTAssertFalse(failed)
        MemoryNotifier.delivery.authorizationStatus = { .provisional }
        MemoryNotifier.delivery.deliverOverride = { _ in }
        let provisional = await MemoryNotifier.notify(entry())
        XCTAssertTrue(provisional)
    }
}
