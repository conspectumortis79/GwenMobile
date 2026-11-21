@testable import GwenMobileFeatureCore
import XCTest

final class SettingsDefaultsTests: XCTestCase {
    private enum ProbeText: String {
        case erster
        case zweiter
    }

    private enum ProbeNumber: Int {
        case eins = 1
        case zwei = 2
    }

    private let suiteName = "gwen.settings-defaults.tests"
    private lazy var suite = UserDefaults(suiteName: suiteName) ?? .standard

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testMissingValuesFallBack() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        XCTAssertTrue(SettingsDefaults.bool(suite, "fehlt", true))
        XCTAssertFalse(SettingsDefaults.bool(suite, "fehlt", false))
        XCTAssertEqual(SettingsDefaults.int(suite, "fehlt", 12), 12)
        XCTAssertEqual(SettingsDefaults.string(suite, "fehlt"), "")
        XCTAssertFalse(SettingsDefaults.flag(suite, "fehlt"))
        XCTAssertEqual(SettingsDefaults.rawValue(suite, "fehlt", ProbeText.erster), .erster)
        XCTAssertEqual(SettingsDefaults.rawValue(suite, "fehlt", ProbeNumber.zwei), .zwei)
        XCTAssertEqual(SettingsDefaults.validChoice(suite, "fehlt", [1, 2, 3], 2), 2)
    }

    func testStoredValuesWin() {
        suite.set(false, forKey: "wahrheit")
        suite.set(7, forKey: "zahl")
        suite.set("wort", forKey: "wort")
        XCTAssertFalse(SettingsDefaults.bool(suite, "wahrheit", true))
        XCTAssertEqual(SettingsDefaults.int(suite, "zahl", 1), 7)
        XCTAssertEqual(SettingsDefaults.string(suite, "wort"), "wort")
        XCTAssertEqual(SettingsDefaults.bool(suite, "wort", true), true)
        XCTAssertEqual(SettingsDefaults.int(suite, "wort", 4), 4)
    }

    func testFlagsReadTheStoredBoolean() {
        suite.set(true, forKey: "an")
        XCTAssertTrue(SettingsDefaults.flag(suite, "an"))
        suite.set(false, forKey: "aus")
        XCTAssertFalse(SettingsDefaults.flag(suite, "aus"))
    }

    func testRawValuesIgnoreMissingAndUnknownStoredValues() {
        suite.set(ProbeText.zweiter.rawValue, forKey: "text")
        XCTAssertEqual(SettingsDefaults.rawValue(suite, "text", ProbeText.erster), .zweiter)
        suite.set("unbekannt", forKey: "text")
        XCTAssertEqual(SettingsDefaults.rawValue(suite, "text", ProbeText.erster), .erster)
        suite.set(ProbeNumber.eins.rawValue, forKey: "nummer")
        XCTAssertEqual(SettingsDefaults.rawValue(suite, "nummer", ProbeNumber.zwei), .eins)
        suite.set(99, forKey: "nummer")
        XCTAssertEqual(SettingsDefaults.rawValue(suite, "nummer", ProbeNumber.zwei), .zwei)
    }

    func testValidChoiceKeepsOnlyOfferedValues() {
        XCTAssertEqual(SettingsDefaults.validChoice(suite, "wahl", [1, 2, 3], 2), 2)
        suite.set(3, forKey: "wahl")
        XCTAssertEqual(SettingsDefaults.validChoice(suite, "wahl", [1, 2, 3], 2), 3)
        suite.set(9, forKey: "wahl")
        XCTAssertEqual(SettingsDefaults.validChoice(suite, "wahl", [1, 2, 3], 2), 2)
    }
}
