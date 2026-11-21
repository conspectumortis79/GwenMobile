@testable import GwenMobile
@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class GwenMobileShellTests: GwenTestCase {
    func testTheShellInstallsOnlyOutsideTheTestHost() {
        let closer = ShareCloserPort.make
        defer { ShareCloserPort.make = closer }
        GwenMobileShell.installSystemsIfNeeded(environment: ["XCTestConfigurationFilePath": "aktiv"])
        XCTAssertTrue(TimerSetterPort.current is StubTimerSetter)
        GwenMobileShell.installSystemsIfNeeded(environment: [:])
        XCTAssertTrue(TimerSetterPort.current is SystemTimerSetter)
        TimerSetterPort.current = StubTimerSetter()
    }

    func testTheListenIntentAsksForListening() async throws {
        let before = ListenRequests.shared.token
        _ = try await ListenIntent().perform()
        XCTAssertEqual(ListenRequests.shared.token, before + 1)
        XCTAssertTrue(ListenIntent.openAppWhenRun)
        _ = ListenIntent.description
        XCTAssertEqual(GwenShortcuts.appShortcuts.count, 1)
    }
}
