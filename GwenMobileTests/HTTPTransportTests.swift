import XCTest
@testable import GwenMobile

final class HTTPTransportTests: XCTestCase {
    func testSecureConnectionFailedIsTheDeviceMeasuredCode1200() {
        XCTAssertEqual(URLError.secureConnectionFailed.rawValue, -1200)
        XCTAssertEqual(URLError(_nsError: NSError(domain: NSURLErrorDomain, code: -1200)).code, .secureConnectionFailed)
    }

    func testTransientConnectionCodesAreRetriedOnce() {
        XCTAssertTrue(HTTP.connectionRetryCodes.contains(.secureConnectionFailed))
        XCTAssertTrue(HTTP.connectionRetryCodes.contains(.networkConnectionLost))
        XCTAssertTrue(HTTP.connectionRetryCodes.contains(.cannotConnectToHost))
    }

    func testCancellationAndTimeoutAreNeverRetried() {
        XCTAssertFalse(HTTP.connectionRetryCodes.contains(.cancelled))
        XCTAssertFalse(HTTP.connectionRetryCodes.contains(.timedOut))
        XCTAssertFalse(HTTP.connectionRetryCodes.contains(.notConnectedToInternet))
    }

    func testBackoffIsShortEnoughToStayInsideTheRequestBudget() {
        XCTAssertLessThan(HTTP.connectionRetryBackoff.components.seconds, 3)
    }

    func testEndpointJoiningCollapsesDuplicateSlashes() {
        XCTAssertEqual(HTTP.endpoint("https://x.example/v1/", "/chat/completions")?.absoluteString,
                       "https://x.example/v1/chat/completions")
        XCTAssertEqual(HTTP.endpoint("https://x.example/v1", "/models")?.absoluteString,
                       "https://x.example/v1/models")
    }
}
