@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class PriceWatchStoreTests: GwenTestCase {
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
        let (store, paths) = makePriceWatchStore()
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

    func testAKeyThatDoesNotMatchDoesNotFallBackToTheTerms() async throws {
        let (store, _) = makePriceWatchStore()
        let created = await store.create(terms: ["PlayStation 5"], goal: 400, intervalHours: 24,
                                         currencyCode: "EUR", regionCode: nil)
        XCTAssertNotNil(created)
        let matched = await store.match(key: "00000000", terms: ["PlayStation 5"])
        XCTAssertNil(matched)
    }

    func testAFailedSaveIsReported() async throws {
        let (store, paths) = makePriceWatchStore()
        let received = LockedValue<String?>(nil)
        store.reportFailures { received.set($0) }
        try makeSupportUnwritable(paths)
        defer { restoreSupport(paths) }
        _ = await store.create(terms: ["Kaffee"], goal: 10, intervalHours: nil,
                               currencyCode: nil, regionCode: nil)
        XCTAssertTrue(received.current?.contains("speichern") ?? false, received.current ?? "keine Meldung")
    }

    func testTwoConfigurationsSharingOneTermStayTheirOwnWatch() async {
        let (store, _) = makePriceWatchStore()
        let first = await store.create(terms: ["iPhone 15", "256GB"], goal: 400,
                                       intervalHours: 6, currencyCode: "EUR", regionCode: nil)
        let second = await store.create(terms: ["iPhone 16", "256GB"], goal: 400,
                                        intervalHours: nil, currencyCode: "EUR", regionCode: nil)
        XCTAssertTrue(first?.created == true)
        XCTAssertTrue(second?.created == true)
        let watches = await store.all()
        XCTAssertEqual(watches.count, 2)
    }

    func testTheSameProductWithAnotherGoalUpdatesTheExistingWatch() async {
        let (store, _) = makePriceWatchStore()
        let first = await store.create(terms: ["PlayStation 5"], goal: 400,
                                       intervalHours: 6, currencyCode: "EUR", regionCode: nil)
        let second = await store.create(terms: ["PlayStation 5"], goal: 500,
                                        intervalHours: nil, currencyCode: "EUR", regionCode: nil)
        XCTAssertTrue(first?.created == true)
        XCTAssertTrue(second?.created == false)
        XCTAssertEqual(second?.watch.goal, 500)
        let watches = await store.all()
        XCTAssertEqual(watches.count, 1)
    }

    func testACreateWithoutAnIntervalKeepsTheExistingCadence() async {
        let (store, _) = makePriceWatchStore()
        _ = await store.create(terms: ["PlayStation 5"], goal: 400,
                               intervalHours: 6, currencyCode: "EUR", regionCode: nil)
        let merged = await store.create(terms: ["PlayStation 5"], goal: 400,
                                        intervalHours: nil, currencyCode: "EUR", regionCode: nil)
        XCTAssertTrue(merged?.created == false)
        XCTAssertEqual(merged?.watch.intervalHours, 6)
        let watches = await store.all()
        XCTAssertEqual(watches.count, 1)
    }

    func testAVeryLargeNumberDoesNotCrashTheConfigurationCheck() {
        let huge = "9223372036854775808"
        XCTAssertTrue(PriceWatch.matchesConfiguration(product: "Modell \(huge)",
                                                      terms: ["Modell \(huge)"]))
    }

    func testTheProductComparisonHandlesContainmentPrefixesAndEmptyTerms() {
        XCTAssertTrue(PriceWatch.sameProduct(["PlayStation 5"], ["PlayStation 5 Slim"]))
        XCTAssertTrue(PriceWatch.sameProduct(["MacBook Air M4 16GB"], ["MacBook Air M4 24GB"]))
        XCTAssertFalse(PriceWatch.sameProduct([], ["PS5"]))
        XCTAssertFalse(PriceWatch.sameProduct(["PS5"], []))
        XCTAssertFalse(PriceWatch.sameProduct([""], ["PS5"]))
        XCTAssertFalse(PriceWatch.sameProduct(["PS5"], ["Switch"]))
    }

    func testAnOfferMustMatchTheWatchedCapacity() {
        let terms = ["M5 Ultra 30 C 64 C 256 GB 1 Terabyte", "M5 Ultra"]
        XCTAssertFalse(PriceWatch.matchesConfiguration(
            product: "Apple Mac Studio 2026 M5 Ultra/256/2TB 30C CPU 64C", terms: terms))
        XCTAssertTrue(PriceWatch.matchesConfiguration(
            product: "Apple Mac Studio 2026 M5 Ultra/256/1TB 30C CPU 64C", terms: terms))
        XCTAssertTrue(PriceWatch.matchesConfiguration(
            product: "Apple Mac Studio 2026 M5 Ultra/256/1TB 30-Core CPU 64-Core GPU", terms: terms))
        XCTAssertFalse(PriceWatch.matchesConfiguration(
            product: "Apple Mac Studio 2026 M5 Ultra/128/1TB 30-Core CPU 64-Core GPU", terms: terms))
        XCTAssertFalse(PriceWatch.matchesConfiguration(
            product: "Apple Mac Studio 2026 M5 Ultra/256GB/1000GB 80-Core GPU", terms: terms))
        XCTAssertTrue(PriceWatch.matchesConfiguration(product: "Apple iPhone 15 128GB", terms: ["iPhone 15"]))
    }

    func testOneDamagedWatchDoesNotDiscardTheOtherWatches() async throws {
        let paths = temporaryPaths("gwen-watch-damaged")
        let failures = FailureReporter(label: "PREISWECKER-test")
        let first = PriceWatch(terms: ["PS5"], goal: 400, currencyCode: "EUR")
        let second = PriceWatch(terms: ["Switch"], goal: 300, currencyCode: "EUR")
        XCTAssertTrue(StorageJSON.write([first, second], to: paths.watches, support: paths.support,
                                        failures: failures))
        var objects = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: paths.watches))
            as? [Any])
        var secondObject = try XCTUnwrap(objects[1] as? [String: Any])
        secondObject["paused"] = "kaputt"
        objects[1] = secondObject
        objects.append("kaputt")
        try JSONSerialization.data(withJSONObject: objects).write(to: paths.watches)
        let store = PriceWatchStore(paths: paths)
        let watches = await store.all()
        XCTAssertEqual(Set(watches.map { $0.terms.first ?? "" }), Set(["PS5", "Switch"]))
        XCTAssertEqual(watches.first { $0.terms == ["Switch"] }?.paused, false)
    }
}
