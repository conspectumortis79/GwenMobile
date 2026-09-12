import XCTest
import EventKit
@testable import GwenMobile

final class CalendarAuthorizationTests: XCTestCase {
    func testDeprecatedAuthorizedStatusIsTheSameValueAsFullAccess() {
        XCTAssertEqual(EKAuthorizationStatus(rawValue: 3), EKAuthorizationStatus.fullAccess)
    }

    func testDeniedAndRestrictedAreNotFullAccess() {
        XCTAssertNotEqual(EKAuthorizationStatus.denied.rawValue, EKAuthorizationStatus.fullAccess.rawValue)
        XCTAssertNotEqual(EKAuthorizationStatus.restricted.rawValue, EKAuthorizationStatus.fullAccess.rawValue)
    }
}
