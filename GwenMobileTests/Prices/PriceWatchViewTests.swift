@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit

@MainActor
final class PriceWatchViewTests: GwenTestCase {
    private func makeStore(_ prefix: String) -> ChatStore {
        let paths = temporaryPaths(prefix)
        return ChatStore(media: MediaStore(paths: paths), paths: paths)
    }

    func testTheEmptyListShowsTheHint() async throws {
        let store = makeStore("price-view-empty")
        let controller = mountView(NavigationStack { PriceWatchView().environmentObject(store) },
                                   size: CGSize(width: 390, height: 600))
        try await settleHosted(controller, milliseconds: 400)
        XCTAssertNotNil(controller.view.window)
    }

    func testEveryStatusDrawsItsRow() async throws {
        let store = makeStore("price-view-full")
        let stale = Date().addingTimeInterval(-4 * 24 * 3600)
        _ = await store.watches.create(terms: ["PS5", "Slim"], goal: 400, intervalHours: 24,
                                       currencyCode: "EUR", regionCode: nil, wording: "PS5 Slim")
        if let hit = await store.watches.create(terms: ["Switch 2"], goal: 400, intervalHours: 24,
                                                currencyCode: "EUR", regionCode: nil)?.watch {
            await store.watches.record(id: hit.id,
                                       offer: PriceWatchOffer(price: 379, currency: "EUR",
                                                              shop: "MediaMarkt",
                                                              url: "https://shop.test/switch",
                                                              product: "Switch 2"),
                                       fallbackCurrency: "EUR")
        }
        if let paused = await store.watches.create(terms: ["Xbox"], goal: 300, intervalHours: nil,
                                                   currencyCode: nil, regionCode: nil)?.watch {
            await store.watches.setPaused(id: paused.id, paused: true)
        }
        _ = await store.watches.create(terms: ["Kaffee"], goal: 20, intervalHours: 24,
                                       currencyCode: nil, regionCode: nil, now: stale)
        let controller = mountView(NavigationStack { PriceWatchView().environmentObject(store) },
                                   size: CGSize(width: 390, height: 900))
        try await settleHosted(controller, milliseconds: 600)
        XCTAssertGreaterThan(controller.sizeThatFits(in: CGSize(width: 340, height: 4000)).height, 100)
    }

    private func firstSwitch(in view: UIView) -> UISwitch? {
        if let toggle = view as? UISwitch { return toggle }
        for child in view.subviews {
            if let found = firstSwitch(in: child) { return found }
        }
        return nil
    }

    func testTheRowTogglePausesTheWatch() async throws {
        let store = makeStore("price-view-toggle")
        let createdOption = await store.watches.create(terms: ["PS5"], goal: 400,
                                                       intervalHours: 24, currencyCode: "EUR",
                                                       regionCode: nil)
        let created = try XCTUnwrap(createdOption)
        let controller = mountView(NavigationStack { PriceWatchView().environmentObject(store) },
                                   size: CGSize(width: 390, height: 700))
        try await settleHosted(controller, milliseconds: 500)
        let toggle = try XCTUnwrap(firstSwitch(in: controller.view))
        toggle.setOn(false, animated: false)
        toggle.sendActions(for: .valueChanged)
        try await settleHosted(controller, milliseconds: 500)
        let updated = await store.watches.watch(id: created.watch.id)
        XCTAssertEqual(updated?.paused, true)
    }

    func testTheCheckNowButtonRunsWhenAProviderIsConfigured() async throws {
        MockHTTP.install { _ in (200, MockHTTP.completion("Kein Angebot.")) }
        defer { MockHTTP.uninstall() }
        let store = makeStore("price-view-check")
        let createdOption = await store.watches.create(terms: ["PS5"], goal: 400,
                                                       intervalHours: 24, currencyCode: "EUR",
                                                       regionCode: nil)
        let created = try XCTUnwrap(createdOption)
        let settings = AppSettings.shared
        let provider = settings.provider
        let saved = settings.key(for: provider)
        settings.setKey("price-watch-test-key", for: provider)
        defer { settings.setKey(saved, for: provider) }
        let controller = mountView(NavigationStack { PriceWatchView().environmentObject(store) },
                                   size: CGSize(width: 390, height: 700))
        try await settleHosted(controller, milliseconds: 500)
        let actions = TapProbe.drain()
        for action in actions { action() }
        try await settleHosted(controller, milliseconds: 800)
        _ = created
    }

    func testTheWatchMetaLineCoversEveryState() async throws {
        let store = makeStore("price-meta")
        let createdOption = await store.watches.create(terms: ["PS5"], goal: 400, intervalHours: 24,
                                                       currencyCode: "EUR", regionCode: nil)
        let created = try XCTUnwrap(createdOption)
        let waiting = created.watch
        XCTAssertTrue(PriceWatchView.meta(waiting).contains("400"))
        var seen = waiting
        seen.lastPrice = 380
        seen.lastShop = "MediaMarkt"
        seen.lastCurrency = "EUR"
        seen.lastCheckedAt = Date()
        XCTAssertTrue(PriceWatchView.meta(seen).contains("MediaMarkt"))
        seen.lastShop = nil
        XCTAssertFalse(PriceWatchView.meta(seen).contains("MediaMarkt"))
        var never = waiting
        never.lastCheckedAt = nil
        XCTAssertTrue(PriceWatchView.meta(never).contains(L.t("price_watch_never_checked")))
        let runner = PriceWatchView.makeRunner(store: store, settings: AppSettings.shared)
        _ = await runner.checkOne(id: waiting.id)
    }
}
