@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class NotificationPermissionTests: GwenTestCase {
    func testTheReportCarriesTheGrantedState() async {
        let received = LockedValue<String?>(nil)
        NotificationPermission.request(reporting: "TEST erlaubt", ask: { true },
                                       report: { received.set($0) })
        await waitUntil { received.current != nil }
        XCTAssertEqual(received.current, "TEST erlaubt=true")
    }

    func testADeniedPermissionIsReportedToo() async {
        let received = LockedValue<String?>(nil)
        NotificationPermission.request(reporting: "TEST erlaubt", ask: { false },
                                       report: { received.set($0) })
        await waitUntil { received.current != nil }
        XCTAssertEqual(received.current, "TEST erlaubt=false")
    }
}
