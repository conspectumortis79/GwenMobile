@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class ListenSwitchTests: GwenTestCase {
    func testOneTapTurnsListeningOnAndTheNextOneOff() {
        XCTAssertEqual(ListenSwitch.tap(isOn: false, configured: true), .turned(on: true))
        XCTAssertEqual(ListenSwitch.tap(isOn: true, configured: true), .turned(on: false))
    }

    func testWithoutAProviderTheTapOpensTheSettingsLikeTheMicrophone() {
        XCTAssertEqual(ListenSwitch.tap(isOn: false, configured: false), .openSettings)
    }

    func testListeningCanAlwaysBeSwitchedOffEvenWithoutAProvider() {
        XCTAssertEqual(ListenSwitch.tap(isOn: true, configured: false), .turned(on: false))
    }

    func testTheNoticeNamesTheNewState() {
        XCTAssertEqual(L.t(ListenSwitch.noticeKey(on: true)), "Listening mode on")
        XCTAssertEqual(L.t(ListenSwitch.noticeKey(on: false)), "Listening mode off")
    }
}
