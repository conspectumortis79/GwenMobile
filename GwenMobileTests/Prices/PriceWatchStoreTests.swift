@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class PriceWatchStoreTests: GwenTestCase {
    private func makeStore() -> (PriceWatchStore, StoragePaths) {
        let paths = temporaryPaths("gwen-watch")
        return (PriceWatchStore(paths: paths), paths)
    }

    func testAForeignCurrencyOfferDoesNotCountAsTheGoal() {
        let watch = PriceWatch(terms: ["PS5"], goal: 400, currencyCode: "EUR",
                               lastPrice: 380, lastCurrency: "USD", hitAt: Date())
        XCTAssertFalse(watch.reached)
        XCTAssertEqual(watch.status, .waiting)
        let dollars = PriceWatchOffer(price: 380, currency: "USD")
        XCTAssertFalse(watch.needsNotification(dollars))
        XCTAssertFalse(PriceWatchCheckOutcome(watch: watch, offer: dollars, failure: nil).hit)
        XCTAssertTrue(watch.needsNotification(PriceWatchOffer(price: 380, currency: "EUR")))
    }

    func testDeleteReturnsTheWatchAndRestoreKeepsItsPosition() async throws {
        let (store, paths) = makeStore()
        let early = Date(timeIntervalSince1970: 1_800_000_000)
        let late = early.addingTimeInterval(60)
        let firstOption = await store.create(terms: ["PS5"], goal: 400, intervalHours: 24,
                                             currencyCode: "EUR", regionCode: nil, now: early)
        let first = try XCTUnwrap(firstOption?.watch)
        let secondOption = await store.create(terms: ["Switch"], goal: 300, intervalHours: 24,
                                              currencyCode: "EUR", regionCode: nil, now: late)
        let second = try XCTUnwrap(secondOption?.watch)
        let deleted = await store.delete(key: first.shortKey, terms: [])
        XCTAssertEqual(deleted?.id, first.id)
        let missing = await store.delete(key: first.shortKey, terms: [])
        XCTAssertNil(missing)
        let gone = try XCTUnwrap(deleted)
        let restored = await store.restore(gone)
        XCTAssertTrue(restored)
        let duplicate = await store.restore(gone)
        XCTAssertFalse(duplicate)
        let all = await store.all()
        XCTAssertEqual(all.map(\.id), [second.id, first.id])
        let reopened = PriceWatchStore(paths: paths)
        let persisted = await reopened.all()
        XCTAssertEqual(persisted.map(\.id), all.map(\.id))
    }

    func testAFailedSaveIsReported() async throws {
        let (store, paths) = makeStore()
        let received = LockedValue<String?>(nil)
        await store.reportFailures { received.set($0) }
        try makeSupportUnwritable(paths)
        defer { restoreSupport(paths) }
        _ = await store.create(terms: ["Kaffee"], goal: 10, intervalHours: nil,
                               currencyCode: nil, regionCode: nil)
        XCTAssertTrue(received.current?.contains("speichern") ?? false, received.current ?? "keine Meldung")
    }
}
