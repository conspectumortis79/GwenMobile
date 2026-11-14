@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class SourceGateTests: GwenTestCase {
    private func reports() -> SourceReports {
        let name = "SourceGateTests.\(UUID().uuidString)"
        addTeardownBlock {
            UserDefaults.standard.removePersistentDomain(forName: name)
        }
        return SourceReports(defaults: UserDefaults(suiteName: name)!, key: "reports")
    }

    func testAReportedDomainIsBlocked() {
        let store = reports()
        store.report("fake.test")
        let gate = SourceGate(reports: store)
        XCTAssertFalse(gate.isBlocked(URL(string: "https://kept.test/a")!))
        XCTAssertTrue(gate.isBlocked(URL(string: "https://fake.test/a")!))
    }

    func testAnAddressWithUserinfoIsBlockedLocally() {
        let gate = SourceGate(reports: reports())
        XCTAssertTrue(gate.isBlocked(URL(string: "https://user@example.org/a")!))
        XCTAssertFalse(gate.isBlocked(URL(string: "https://example.org/a")!))
    }
}
