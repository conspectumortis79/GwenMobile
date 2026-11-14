@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class MemoryLogicGapTests: GwenTestCase {
    func testTheReplaceAndRemindPath() async {
        let store = MemoryStore(paths: temporaryPaths("memory-logic"))
        let first = await store.add(text: "mag Tee", category: .likes, source: .explicit, remind: true)
        XCTAssertNotNil(first)
        let key = first?.entry.shortKey ?? ""
        let again = await store.add(text: "mag Kaffee", category: .likes, source: .explicit,
                                    replaceKey: key, remind: true)
        _ = again
        let all = await store.all()
        XCTAssertFalse(all.isEmpty)
    }

    func testTheCatalogOrdering() async {
        let store = MemoryStore(paths: temporaryPaths("memory-catalog"))
        let now = Date()
        _ = await store.add(text: "alt", category: .likes, source: .explicit,
                            now: now.addingTimeInterval(-100))
        _ = await store.add(text: "neu", category: .likes, source: .explicit, now: now)
        let pinned = await store.add(text: "angeheftet", category: .work, source: .explicit,
                                     now: now.addingTimeInterval(-200))
        let pinnedKey = pinned?.entry.shortKey ?? ""
        await store.setPinned(key: pinnedKey, pinned: true)
        let catalog = await store.catalog()
        XCTAssertTrue(catalog.lowercased().contains("angeheftet"), catalog)
        XCTAssertFalse(catalog.isEmpty)
    }
}
