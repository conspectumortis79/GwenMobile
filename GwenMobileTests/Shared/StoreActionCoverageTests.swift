@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class StoreActionCoverageTests: GwenTestCase {
    private func makeStore(_ prefix: String) -> ChatStore {
        let paths = temporaryPaths(prefix)
        return ChatStore(media: MediaStore(paths: paths), paths: paths)
    }

    func testThePriceWatchRowActionsChangeTheStore() async throws {
        let store = makeStore("price-actions")
        let createdOption = await store.watches.create(terms: ["PS5"], goal: 400, intervalHours: 24,
                                                       currencyCode: nil, regionCode: nil)
        let created = try XCTUnwrap(createdOption)
        await PriceWatchView.setPaused(created.watch, paused: true, store: store)
        let paused = await store.watches.watch(id: created.watch.id)
        XCTAssertEqual(paused?.paused, true)
        await PriceWatchView.setPaused(created.watch, paused: false, store: store)
        let resumed = await store.watches.watch(id: created.watch.id)
        XCTAssertEqual(resumed?.paused, false)
        let deleted = await PriceWatchView.delete(created.watch, store: store)
        XCTAssertEqual(deleted?.id, created.watch.id)
        let all = await store.watches.all()
        XCTAssertTrue(all.isEmpty)
        let gone = try XCTUnwrap(deleted)
        let restored = await store.watches.restore(gone)
        XCTAssertTrue(restored)
        let restoredAll = await store.watches.all()
        XCTAssertEqual(restoredAll.map(\.id), [created.watch.id])
    }

    func testTheMemoryRowActionsChangeTheStore() async throws {
        let store = makeStore("memory-actions")
        let created = await store.memory.add(text: "mag Tee", category: .likes, source: .manual)
        let entry = try XCTUnwrap(created?.entry)
        await MemoryView.togglePin(entry: entry, store: store)
        let pinned = await store.memory.entry(key: entry.shortKey)
        XCTAssertEqual(pinned?.pinned, true)
        let pinnedEntry = try XCTUnwrap(pinned)
        await MemoryView.togglePin(entry: pinnedEntry, store: store)
        let unpinned = await store.memory.entry(key: entry.shortKey)
        XCTAssertEqual(unpinned?.pinned, false)
        let unpinnedEntry = try XCTUnwrap(unpinned)
        let index = await MemoryView.remove(entry: unpinnedEntry, store: store)
        XCTAssertEqual(index, 0)
        let after = await store.memory.all()
        XCTAssertTrue(after.isEmpty)
        let restored = await store.memory.restore(unpinnedEntry, at: try XCTUnwrap(index))
        XCTAssertTrue(restored)
        let restoredEntries = await store.memory.all()
        XCTAssertEqual(restoredEntries.map(\.id), [unpinnedEntry.id])
    }
}
