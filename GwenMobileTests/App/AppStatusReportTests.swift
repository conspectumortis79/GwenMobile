@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import UserNotifications
import XCTest
import GwenMobileKit

@MainActor
final class AppStatusReportTests: GwenTestCase {
    func testAProviderWithoutAKeyIsNoProblemWhenTheKeyIsOptional() {
        let optional = AppStatusReader.keyRow(blocked: false, present: false, optional: true)
        XCTAssertEqual(optional.value, L.t("app_status_value_optional"))
        XCTAssertEqual(optional.level, .ok)
        let missing = AppStatusReader.keyRow(blocked: false, present: false, optional: false)
        XCTAssertEqual(missing.value, L.t("app_status_value_missing"))
        XCTAssertEqual(missing.level, .problem)
        let present = AppStatusReader.keyRow(blocked: false, present: true, optional: false)
        XCTAssertEqual(present.value, L.t("app_status_value_present"))
        XCTAssertEqual(present.level, .ok)
        let blocked = AppStatusReader.keyRow(blocked: true, present: true, optional: true)
        XCTAssertEqual(blocked.value, L.t("app_status_value_blocked"))
        XCTAssertEqual(blocked.level, .problem)
    }

    func testOnlyTheLocalProvidersTreatTheKeyAsOptional() {
        let connections = ProviderConnections()
        XCTAssertTrue(ProviderID.local.descriptor.keyIsOptional(connections))
        XCTAssertFalse(ProviderID.qwenCloud.descriptor.keyIsOptional(connections))
        XCTAssertFalse(ProviderID.openRouter.descriptor.keyIsOptional(connections))
        XCTAssertFalse(ProviderID.deepSeek.descriptor.keyIsOptional(connections))
        XCTAssertFalse(ProviderID.openAICompatible.descriptor.keyIsOptional(connections))
        var ollama = connections
        ollama.openAICompatible.select(presetID: "ollama")
        XCTAssertTrue(ProviderID.openAICompatible.descriptor.keyIsOptional(ollama))
    }

    func testNotificationsThatWereNeverAskedForAreNotShownAsDenied() {
        let unasked = AppStatusReader.notificationRow(.notDetermined)
        XCTAssertEqual(unasked.value, L.t("app_status_value_not_determined"))
        XCTAssertEqual(unasked.level, .attention)
        let denied = AppStatusReader.notificationRow(.denied)
        XCTAssertEqual(denied.value, L.t("app_status_value_denied"))
        XCTAssertEqual(denied.level, .attention)
        for allowed in [UNAuthorizationStatus.authorized, .provisional, .ephemeral] {
            let row = AppStatusReader.notificationRow(allowed)
            XCTAssertEqual(row.value, L.t("app_status_value_allowed"))
            XCTAssertEqual(row.level, .ok)
        }
    }
}
