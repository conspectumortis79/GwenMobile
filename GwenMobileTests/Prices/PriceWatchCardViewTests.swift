@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit

@MainActor
final class PriceWatchCardViewTests: GwenTestCase {
    private func ref(status: PriceWatch.Status, url: String? = "https://shop.test/ps5",
                     best: Double? = 449, bestProduct: String? = "PS5 Disc",
                     checked: Date? = Date()) -> PriceWatchRef {
        PriceWatchRef(watch: PriceWatch(terms: ["PlayStation 5", "Slim"], goal: 400, wording: "PS5 Slim",
                                        currencyCode: "EUR", paused: status == .paused,
                                        lastCheckedAt: checked, lastPrice: best, lastCurrency: "EUR",
                                        lastShop: "MediaMarkt", lastURL: url, lastProduct: bestProduct,
                                        hitAt: status == .hit ? Date() : nil))
    }

    func testEveryStatusDrawsItsOwnCard() {
        XCTAssertNotNil(renderView(PriceWatchCardView(ref: ref(status: .waiting)), width: 300))
        XCTAssertNotNil(renderView(PriceWatchCardView(ref: ref(status: .hit, best: 379)), width: 300))
        XCTAssertNotNil(renderView(PriceWatchCardView(ref: ref(status: .paused)), width: 300))
    }

    func testTheCardDrawsWithoutAnOfferLinkOrPrice() async throws {
        let empty = ref(status: .waiting, url: nil, best: nil, bestProduct: nil, checked: nil)
        let controller = mountView(PriceWatchCardView(ref: empty), size: CGSize(width: 320, height: 300))
        try await settleHosted(controller)
        XCTAssertNotNil(renderView(PriceWatchCardView(ref: empty), width: 300))
    }

    func testTheBestProductIsHiddenWhenItNamesTheWatchItself() {
        let same = ref(status: .waiting, bestProduct: "ps5 slim")
        XCTAssertNotNil(renderView(PriceWatchCardView(ref: same), width: 300))
        let other = ref(status: .waiting, bestProduct: "PS5 Slim Digital")
        XCTAssertNotNil(renderView(PriceWatchCardView(ref: other), width: 300))
    }

    func testTheCardDrawsWithACompletedCheckAndAnOffer() async throws {
        let controller = mountView(PriceWatchCardView(ref: ref(status: .hit, best: 379)),
                                   size: CGSize(width: 320, height: 300))
        try await settleHosted(controller)
        XCTAssertGreaterThan(controller.sizeThatFits(in: CGSize(width: 300, height: 2000)).height, 60)
    }
}
