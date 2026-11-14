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

    func testAnUnsafeRedirectIsNotFollowed() throws {
        let redirects = HTTPRedirectGuard()
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let url = try XCTUnwrap(URL(string: "https://example.test/start"))
        let task = session.dataTask(with: URLRequest(url: url))
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1",
                                                     headerFields: nil))
        let target = try XCTUnwrap(URL(string: "http://127.0.0.1/secret"))
        let followed = LockedValue<URLRequest?>(nil)
        redirects.urlSession(session, task: task, willPerformHTTPRedirection: response,
                             newRequest: URLRequest(url: target)) { followed.set($0) }
        XCTAssertNil(followed.current)
        XCTAssertEqual(redirects.blocked, target)
    }

    func testASafeRedirectIsFollowed() throws {
        let redirects = HTTPRedirectGuard()
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let url = try XCTUnwrap(URL(string: "https://example.test/start"))
        let task = session.dataTask(with: URLRequest(url: url))
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1",
                                                     headerFields: nil))
        let target = try XCTUnwrap(URL(string: "https://example.com/next"))
        let followed = LockedValue<URLRequest?>(nil)
        redirects.urlSession(session, task: task, willPerformHTTPRedirection: response,
                             newRequest: URLRequest(url: target)) { followed.set($0) }
        XCTAssertEqual(followed.current?.url, target)
        XCTAssertNil(redirects.blocked)
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

private class UnsafeRedirectProtocol: URLProtocol {
    static let target = URL(string: "http://127.0.0.1/secret")!

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "example.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1",
                                             headerFields: ["Location": Self.target.absoluteString])
        else { return }
        client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: Self.target), redirectResponse: response)
    }

    override func stopLoading() {}
}

final class HTTPBaseURLGuardTests: XCTestCase {
    func testHTTPDataRejectsAnUnsafeRedirectBeforeFollowingIt() async throws {
        let previous = HTTP.session
        HTTP.session = HTTP.makeSession(protocolClasses: [UnsafeRedirectProtocol.self])
        defer { HTTP.session = previous }
        let url = try XCTUnwrap(URL(string: "https://example.test/start"))
        do {
            _ = try await HTTP.data(URLRequest(url: url))
            XCTFail("erwartet abgelehnt")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 403)
        }
    }

    func testHTTPStreamRejectsAnUnsafeRedirectBeforeFollowingIt() async throws {
        let previous = HTTP.session
        HTTP.session = HTTP.makeSession(protocolClasses: [UnsafeRedirectProtocol.self])
        defer { HTTP.session = previous }
        let url = try XCTUnwrap(URL(string: "https://example.test/start"))
        var request = URLRequest(url: url)
        request.timeoutInterval = 1
        do {
            _ = try await HTTP.streamData(request)
            XCTFail("erwartet abgelehnt")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 403)
        }
    }

    func testAValidatedResponseRejectsABlockedRedirect() throws {
        let url = try XCTUnwrap(URL(string: "https://example.test/start"))
        let target = try XCTUnwrap(URL(string: "http://127.0.0.1/secret"))
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1",
                                                     headerFields: nil))
        let redirects = HTTPRedirectGuard(blockedURL: target)
        do {
            _ = try HTTP.validated((Data(), response), redirects: redirects)
            XCTFail("erwartet abgelehnt")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 403)
        }
    }

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
