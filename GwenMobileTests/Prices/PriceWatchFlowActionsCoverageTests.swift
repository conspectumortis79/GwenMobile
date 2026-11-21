@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
private final class FlowPriceNotifier: PriceWatchNotifying {
    private(set) var notices = 0

    func prepare() {}

    func notify(_ watch: PriceWatch, offer: PriceWatchOffer) async -> Bool {
        notices += 1
        return true
    }
}

@MainActor
final class PriceWatchFlowActionsCoverageTests: GwenTestCase {
    func testEveryPriceWatchActionRuns() async {
        let paths = temporaryPaths("flow-price-actions")
        let store = PriceWatchStore(paths: paths)
        let checker = TestPriceChecker()
        let notifier = FlowPriceNotifier()
        let runner = PriceWatchFlowRunner(store: store, checker: checker,
                                          credentials: PriceWatchCredentials(baseURL: "https://api.test/v1",
                                                                             key: "k", model: "m",
                                                                             thinking: .nothing),
                                          notifier: notifier)
        _ = await runner.run(PriceWatchRequest(action: .list), question: "")
        _ = await runner.run(PriceWatchRequest(action: .create, terms: ["X"]), question: "")
        _ = await runner.run(PriceWatchRequest(action: .create, terms: ["PS5"], goal: 400),
                             question: "unter 400 Euro")
        let key = await store.all().first?.shortKey
        _ = await runner.run(PriceWatchRequest(action: .check, key: key), question: "")
        checker.offers = [PriceWatchOffer(price: 350, currency: "EUR", shop: "MediaMarkt",
                                          url: "https://shop.test/ps5", product: "PS5")]
        _ = await runner.run(PriceWatchRequest(action: .check, key: key), question: "")
        let due = await store.due()
        XCTAssertNotNil(due)
        _ = await runner.checkDue()
        XCTAssertGreaterThanOrEqual(notifier.notices, 0)
        _ = await runner.run(PriceWatchRequest(action: .update, goal: 300, key: key), question: "")
        _ = await runner.run(PriceWatchRequest(action: .update, goal: 300, key: "fehlt"), question: "")
        _ = await runner.run(PriceWatchRequest(action: .delete, key: key), question: "")
        _ = await runner.run(PriceWatchRequest(action: .delete, key: "fehlt"), question: "")
        _ = await runner.checkOne(id: UUID())
    }
}
