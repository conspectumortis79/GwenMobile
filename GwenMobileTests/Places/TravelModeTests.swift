@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class TravelModeTests: GwenTestCase {
    func testEveryModeNamesItselfAndItsMapsOption() {
        for mode in TravelMode.allCases {
            XCTAssertFalse(mode.labelKey.isEmpty, mode.rawValue)
            XCTAssertEqual(mode.label, L.t(mode.labelKey))
            XCTAssertFalse(mode.launchOption.isEmpty, mode.rawValue)
        }
        XCTAssertEqual(TravelMode.driving.mapsURLFlag, "d")
        XCTAssertEqual(TravelMode.walking.mapsURLFlag, "w")
        XCTAssertNil(TravelMode.transit.mapsURLFlag)
        XCTAssertNil(TravelMode.cycling.mapsURLFlag)
        XCTAssertNil(TravelMode.automatic.mapsURLFlag)
    }
}
