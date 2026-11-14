@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class SourceReportsTests: GwenTestCase {
    private func suite() -> UserDefaults {
        let name = "SourceReportsTests.\(UUID().uuidString)"
        addTeardownBlock {
            UserDefaults.standard.removePersistentDomain(forName: name)
        }
        return UserDefaults(suiteName: name)!
    }

    func testAReportIsRememberedAndCanBeWithdrawn() {
        let reports = SourceReports(defaults: suite(), key: "reports")
        XCTAssertFalse(reports.isReported("example.org"))
        reports.report("www.example.org")
        XCTAssertTrue(reports.isReported("EXAMPLE.ORG"))
        XCTAssertEqual(reports.count("example.org"), 1)
        reports.report("example.org")
        XCTAssertEqual(reports.count("example.org"), 2)
        reports.withdraw("example.org")
        XCTAssertFalse(reports.isReported("example.org"))
    }

    func testAReportSurvivesAReload() {
        let defaults = suite()
        SourceReports(defaults: defaults, key: "reports").report("fake.test")
        let reloaded = SourceReports(defaults: defaults, key: "reports")
        XCTAssertTrue(reloaded.isReported("fake.test"))
        XCTAssertEqual(reloaded.reportedDomains, ["fake.test"])
    }

    func testAnEmptyReportIsIgnored() {
        let reports = SourceReports(defaults: suite(), key: "reports")
        reports.report("   ")
        XCTAssertTrue(reports.reportedDomains.isEmpty)
    }
}
