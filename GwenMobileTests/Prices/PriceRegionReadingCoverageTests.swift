@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import CoreLocation
import XCTest
import GwenMobileKit

private struct RegionFakeFixer: LocationFixing {
    var location = CLLocation(latitude: 48.137, longitude: 11.575)
    var error: Error?

    func fix() async throws -> CLLocation {
        if let error { throw error }
        return location
    }
}

@MainActor
private final class RegionFakeGeocoder: CountryGeocoding {
    var code: String?
    var error: Error?

    init(code: String? = nil, error: Error? = nil) {
        self.code = code
        self.error = error
    }

    func country(at location: CLLocation) async throws -> String? {
        if let error { throw error }
        return code
    }
}

@MainActor
final class PriceRegionReadingCoverageTests: GwenTestCase {
    func testANamedCountryWins() async {
        let reading = LivePriceRegionReading(fixer: RegionFakeFixer(), geocoder: RegionFakeGeocoder())
        let region = await reading.region(named: "Polen", whenLocalWish: false)
        XCTAssertEqual(region.code, "PL")
        XCTAssertEqual(region.source, .named)
    }

    func testTheNearbyWishUsesTheLocatedCountry() async {
        let reading = LivePriceRegionReading(fixer: RegionFakeFixer(),
                                             geocoder: RegionFakeGeocoder(code: "AT"))
        let region = await reading.region(named: nil, whenLocalWish: true)
        XCTAssertEqual(region.code, "AT")
        XCTAssertEqual(region.source, .located)
    }

    func testAMissingCountryFallsBackToTheDevice() async {
        let reading = LivePriceRegionReading(fixer: RegionFakeFixer(),
                                             geocoder: RegionFakeGeocoder(code: nil))
        let region = await reading.region(named: nil, whenLocalWish: true)
        XCTAssertEqual(region, PriceRegion.device())
        let plain = await reading.region(named: nil, whenLocalWish: false)
        XCTAssertEqual(plain, PriceRegion.device())
    }

    func testAFailingLookupFallsBack() async {
        let failingFixer = LivePriceRegionReading(fixer: RegionFakeFixer(error: APIError(message: "kein ort")),
                                                  geocoder: RegionFakeGeocoder(code: "DE"))
        let fallback = await failingFixer.region(named: nil, whenLocalWish: true)
        XCTAssertEqual(fallback, PriceRegion.device())
        let failingGeocoder = LivePriceRegionReading(fixer: RegionFakeFixer(),
                                                     geocoder: RegionFakeGeocoder(error: APIError(message: "x")))
        let failed = await failingGeocoder.region(named: nil, whenLocalWish: true)
        XCTAssertEqual(failed, PriceRegion.device())
    }
}

@MainActor
final class PriceWatchBackgroundCoverageTests: GwenTestCase {
    override func setUp() {
        super.setUp()
        MockHTTP.install(MockHTTP.defaultHandler)
    }

    override func tearDown() {
        MockHTTP.uninstall()
        super.tearDown()
    }

    func testSchedulingWithoutAWatchCancelsTheTask() async {
        let paths = temporaryPaths("price-bg-empty")
        let store = PriceWatchStore(paths: paths)
        await PriceWatchBackground.scheduleNext(store: store)
        let due = await store.nextDueDate()
        XCTAssertNil(due)
        XCTAssertEqual(PriceWatchBackgroundSystem.taskIdentifier, "com.mortis.gwenmobile.pricecheck")
        XCTAssertGreaterThan(PriceWatchBackgroundSystem.minimumDelay, 0)
    }

    func testSchedulingWithADueWatchSubmits() async {
        let paths = temporaryPaths("price-bg-due")
        let store = PriceWatchStore(paths: paths)
        _ = await store.create(terms: ["PS5"], goal: 400, intervalHours: 24, currencyCode: "EUR",
                               regionCode: nil, now: Date().addingTimeInterval(-3 * 86_400))
        await PriceWatchBackground.scheduleNext(store: store)
        let due = await store.nextDueDate()
        XCTAssertNotNil(due)
    }

    func testHandlingWithoutATaskGoesThroughTheStubPort() async {
        XCTAssertTrue(PriceWatchBackgroundPort.current is StubPriceWatchBackground)
        await PriceWatchBackgroundPort.current.handle(nil)
        XCTAssertTrue(PriceWatchBackgroundPort.current is StubPriceWatchBackground)
    }
}
