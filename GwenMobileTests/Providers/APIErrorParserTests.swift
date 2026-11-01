@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

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

    func testErrorCarriedAsAPlainStringIsRead() {
        XCTAssertEqual(APIErrorParser.message(from: #"{"error":"boom"}"#, status: 400), "boom")
    }

    func testDetailCarriedErrorIsReadInsteadOfTheRawJSON() {
        XCTAssertEqual(APIErrorParser.message(from: #"{"detail":"quota erschöpft"}"#, status: 429),
                       "quota erschöpft")
    }

    func testNumericErrorCodeIsCombinedWithTheMessage() {
        XCTAssertEqual(APIErrorParser.message(from: #"{"error":{"code":429,"message":"slow down"}}"#, status: 429),
                       "429: slow down")
    }

    func testCodeOnlyAPIErrorFallsBackToStatusLine() {
        XCTAssertEqual(APIErrorParser.message(from: #"{"error":{"code":"NoQuota"}}"#, status: 403), "HTTP 403")
    }

    func testAnErrorFramedAsAnSSELineIsReadWithoutTheTransportPrefix() {
        let body = #"data: {"error":{"code":"invalid_parameter_error","message":"Download timed out"}}"#
        XCTAssertEqual(APIErrorParser.message(from: body, status: 400), "invalid_parameter_error: Download timed out")
    }

    func testSeveralSSELinesOfAnErrorResponseAreReadTogetherAndDoneIsIgnored() {
        let body = "data: [DONE]\ndata: {\"error\":{\"message\":\"stream ended\"}}"
        XCTAssertEqual(APIErrorParser.message(from: body, status: 200), "stream ended")
    }

    func testNativeTopLevelErrorObject() {
        XCTAssertEqual(APIErrorParser.message(from: #"{"code":"ModelNotExists","message":"gone"}"#, status: 404),
                       "ModelNotExists: gone")
    }

    func testNonJSONBodyIsStrippedAndStillCappedAtTwoHundredCharacters() {
        let body = "<html>" + String(repeating: "x", count: 400) + "</html>"
        let message = APIErrorParser.message(from: body, status: 502)
        XCTAssertEqual(message.count, 200)
        XCTAssertFalse(message.contains("<"))
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

    func testSmokeSuccessfulAPIResponseDoesNotThrow() throws {
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

    func testGatewayMarkupIsStrippedInsteadOfShownToTheUser() {
        let body = "<html><body><h1>Bad Gateway</h1><p>nginx</p></body></html>"
        let message = APIErrorParser.message(from: body, status: 502)
        XCTAssertEqual(message, "Bad Gateway nginx")
    }

    func testPureBoilerplatePageFallsBackToTheStatusCode() {
        let body = "<html><head><style>body{color:red}</style><script>var x = 1;</script></head><body></body></html>"
        XCTAssertEqual(APIErrorParser.message(from: body, status: 502), "HTTP 502")
        XCTAssertEqual(APIErrorParser.message(from: "<!doctype html><html></html>", status: 503), "HTTP 503")
    }

    func testTheSharedStripperDropsInvisibleBlocksAndDecodesEntities() {
        let markup = "<script>var a=1;</script><h1>Zwei &amp; drei</h1><p>text</p>"
        XCTAssertEqual(HTMLText.plain(markup, hiding: HTMLText.invisibleBlocks), "Zwei & drei text")
        XCTAssertEqual(HTMLText.plain("<nav>los</nav><p>bleibt</p>", hiding: HTMLText.pageNoiseBlocks),
                       "bleibt")
        XCTAssertEqual(HTMLText.plain("<b>hallo</b>", hiding: []), "hallo")
    }
}
