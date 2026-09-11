import XCTest
@testable import GwenMobile

final class APIErrorParserTests: XCTestCase {
    private let url = URL(string: "https://example.invalid/compatible-mode/v1/chat/completions")!

    private func response(_ code: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!
    }

    func testCodeAndMessageAreCombined() {
        let body = #"{"error":{"code":"Throttling","message":"rate limit"}}"#
        XCTAssertEqual(APIErrorParser.message(from: body, status: 429), "Throttling: rate limit")
    }

    func testMessageOnlyError() {
        XCTAssertEqual(APIErrorParser.message(from: #"{"error":{"message":"boom"}}"#, status: 500), "boom")
    }

    func testCodeOnlyAPIErrorFallsBackToStatusLine() {
        XCTAssertEqual(APIErrorParser.message(from: #"{"error":{"code":"NoQuota"}}"#, status: 403), "HTTP 403")
    }

    func testNativeTopLevelErrorObject() {
        XCTAssertEqual(APIErrorParser.message(from: #"{"code":"ModelNotExists","message":"gone"}"#, status: 404),
                       "ModelNotExists: gone")
    }

    func testNonJSONBodyIsTruncatedToTwoHundredCharacters() {
        let body = "<html>" + String(repeating: "x", count: 400) + "</html>"
        let message = APIErrorParser.message(from: body, status: 502)
        XCTAssertEqual(message.count, 200)
        XCTAssertTrue(message.hasPrefix("<html>"))
    }

    func testEmptyBodyFallsBackToStatus() {
        XCTAssertEqual(APIErrorParser.message(from: "   ", status: 500), "HTTP 500")
    }

    func testAPIFailureCarriesStatusForTheErrorTranslator() {
        let data = Data(#"{"error":{"code":"InvalidApiKey","message":"bad"}}"#.utf8)
        XCTAssertThrowsError(try HTTP.ensureAPISuccess(response(401), data: data)) { error in
            let api = error as? APIError
            XCTAssertEqual(api?.message, "InvalidApiKey: bad")
            XCTAssertEqual(api?.status, 401)
        }
    }

    func testSuccessfulAPIResponseDoesNotThrow() throws {
        try HTTP.ensureAPISuccess(response(200), data: Data("{}".utf8))
        try HTTP.ensureSuccess(response(204))
    }

    func testPlainTransportFailureKeepsStatusMessageWithoutCode() {
        XCTAssertThrowsError(try HTTP.ensureSuccess(response(403))) { error in
            let api = error as? APIError
            XCTAssertEqual(api?.message, "HTTP 403")
            XCTAssertNil(api?.status)
        }
    }
}
