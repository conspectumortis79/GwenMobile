@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class HTTPLocalResponderTests: XCTestCase {
    func testTheLocalResponderShortCircuitsTheSession() async throws {
        let previous = HTTP.localResponder
        defer { HTTP.localResponder = previous }
        let url = try XCTUnwrap(URL(string: "https://example.test/local"))
        HTTP.localResponder = { request in
            let response = try? XCTUnwrap(HTTPURLResponse(url: request.url ?? url, statusCode: 200,
                                                         httpVersion: nil, headerFields: nil))
            return (Data("lokal".utf8), response ?? URLResponse(url: url, mimeType: nil,
                                                               expectedContentLength: 5,
                                                               textEncodingName: nil))
        }
        let (data, response) = try await HTTP.data(URLRequest(url: url))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "lokal")
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }
}
