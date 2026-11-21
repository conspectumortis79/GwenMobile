@testable import GwenMobileFeatureCore
import XCTest

final class ResearchSettingsTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: SettingsKey.researchVerifySources)
        super.tearDown()
    }

    func testTheCitationCheckIsOffUntilTheUserTurnsItOn() {
        UserDefaults.standard.removeObject(forKey: SettingsKey.researchVerifySources)
        XCTAssertFalse(ResearchSettings.load().verifySources)
    }

    func testTheChoiceSurvivesTheNextLoad() {
        UserDefaults.standard.removeObject(forKey: SettingsKey.researchVerifySources)
        var settings = ResearchSettings.load()
        settings.verifySources = true
        settings.store()
        XCTAssertTrue(ResearchSettings.load().verifySources)
        settings.verifySources = false
        settings.store()
        XCTAssertFalse(ResearchSettings.load().verifySources)
    }
}
