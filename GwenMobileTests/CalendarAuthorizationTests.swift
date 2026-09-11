import XCTest
import EventKit
@testable import GwenMobile

final class CalendarAuthorizationTests: XCTestCase {
    func testDeprecatedAuthorizedStatusIsTheSameValueAsFullAccess() {
        XCTAssertEqual(EKAuthorizationStatus.authorized.rawValue, EKAuthorizationStatus.fullAccess.rawValue)
    }

    func testDeniedAndRestrictedAreNotFullAccess() {
        XCTAssertNotEqual(EKAuthorizationStatus.denied.rawValue, EKAuthorizationStatus.fullAccess.rawValue)
        XCTAssertNotEqual(EKAuthorizationStatus.restricted.rawValue, EKAuthorizationStatus.fullAccess.rawValue)
    }
}
