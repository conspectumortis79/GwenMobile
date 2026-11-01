@testable import GwenMobile
@testable import GwenMobileDevice
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
}
