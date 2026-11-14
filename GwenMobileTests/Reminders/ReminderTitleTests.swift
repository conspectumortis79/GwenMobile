@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class ReminderTitleTests: GwenTestCase {
    func testSeveralTitlesAreJoinedInTheOrderTheyCame() {
        XCTAssertEqual(ReminderTitle.merged(["Brot kaufen", "Butter kaufen", "Kaffee kaufen"]),
                       "Brot kaufen, Butter kaufen, Kaffee kaufen")
        XCTAssertEqual(ReminderTitle.merged(["Milch", "Brot"]), "Milch, Brot")
    }

    func testASingleTitleStaysUntouched() {
        XCTAssertEqual(ReminderTitle.merged(["Brot kaufen"]), "Brot kaufen")
        XCTAssertEqual(ReminderTitle.merged(["  Brot kaufen  "]), "Brot kaufen")
    }

    func testNothingAtAllStaysEmpty() {
        XCTAssertEqual(ReminderTitle.merged([]), "")
        XCTAssertEqual(ReminderTitle.merged(["", "   "]), "")
    }
}
