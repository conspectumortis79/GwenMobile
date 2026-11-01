@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

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

    func testOnlyRequestsThatMaySafelyRepeatAreRetried() throws {
        var get = URLRequest(url: try XCTUnwrap(URL(string: "https://x.example/v1/models")))
        get.httpMethod = "GET"
        XCTAssertTrue(HTTP.isIdempotent(get))
        XCTAssertTrue(HTTP.canRetry(URLError(.networkConnectionLost), request: get))

        var post = URLRequest(url: try XCTUnwrap(URL(string: "https://x.example/v1/chat/completions")))
        post.httpMethod = "POST"
        XCTAssertFalse(HTTP.isIdempotent(post))
        XCTAssertFalse(HTTP.canRetry(URLError(.networkConnectionLost), request: post))
        XCTAssertTrue(HTTP.canRetry(URLError(.cannotConnectToHost), request: post))
        XCTAssertTrue(HTTP.canRetry(URLError(.secureConnectionFailed), request: post))
        XCTAssertFalse(HTTP.canRetry(URLError(.timedOut), request: post))
        XCTAssertTrue(HTTP.unreachedConnectionCodes.contains(.secureConnectionFailed))
        XCTAssertFalse(HTTP.unreachedConnectionCodes.contains(.networkConnectionLost))
    }

    func testBackoffIsShortEnoughToStayInsideTheRequestBudget() {
        XCTAssertLessThan(HTTP.connectionRetryBackoff.components.seconds, 3)
    }

    func testEndpointJoiningCollapsesDuplicateSlashes() {
        XCTAssertEqual(HTTP.endpoint("https://x.example/v1/", "/chat/completions")?.absoluteString,
                       "https://x.example/v1/chat/completions")
        XCTAssertEqual(HTTP.endpoint("https://x.example/v1", "/models")?.absoluteString,
                       "https://x.example/v1/models")
        XCTAssertEqual(HTTP.endpoint("https://x.example/v1//", "/chat/completions")?.absoluteString,
                       "https://x.example/v1/chat/completions")
        XCTAssertEqual(HTTP.endpoint("https://x.example///", "/models")?.absoluteString,
                       "https://x.example/models")
    }
}

final class HTTPBaseURLGuardTests: XCTestCase {
    func testAnEmptyOrSchemelessBaseURLIsNotTurnedIntoARelativeRequest() {
        XCTAssertNil(HTTP.endpoint("", "/models"))
        XCTAssertNil(HTTP.endpoint("   ", "/models"))
        XCTAssertNil(HTTP.endpoint("localhost:11434/v1", "/models"))
        XCTAssertNil(HTTP.endpoint("localhost:11434/v1", APIEndpoint.chatCompletions))
        XCTAssertEqual(HTTP.endpoint("http://localhost:11434/v1", "/models")?.absoluteString,
                       "http://localhost:11434/v1/models")
    }

    func testThePictureDownloadCarriesItsOwnTimeout() {
        XCTAssertEqual(APITimeout.imageDownload, 120)
        XCTAssertLessThan(APITimeout.imageDownload, APITimeout.streamResource)
    }
}
