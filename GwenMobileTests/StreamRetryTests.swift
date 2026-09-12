import XCTest
@testable import GwenMobile

final class StreamRetryTests: XCTestCase {
    private func urlError(_ code: URLError.Code) -> URLError {
        URLError(code)
    }

    func testConnectionResetBeforeTheFirstByteIsWorthARetry() {
        XCTAssertTrue(QwenAPI.streamReset(of: urlError(.secureConnectionFailed), sawData: false))
        XCTAssertTrue(QwenAPI.streamReset(of: urlError(.networkConnectionLost), sawData: false))
        XCTAssertTrue(QwenAPI.streamReset(of: urlError(.cannotConnectToHost), sawData: false))
    }

    func testResetAfterTheFirstChunkNeverRestartsTheAnswer() {
        XCTAssertFalse(QwenAPI.streamReset(of: urlError(.secureConnectionFailed), sawData: true))
        XCTAssertFalse(QwenAPI.streamReset(of: urlError(.networkConnectionLost), sawData: true))
    }

    func testUserCancellationAndHardFailuresStayUntouched() {
        XCTAssertFalse(QwenAPI.streamReset(of: urlError(.cancelled), sawData: false))
        XCTAssertFalse(QwenAPI.streamReset(of: urlError(.timedOut), sawData: false))
        XCTAssertFalse(QwenAPI.streamReset(of: urlError(.notConnectedToInternet), sawData: false))
        XCTAssertFalse(QwenAPI.streamReset(of: APIError(message: "HTTP 500", status: 500), sawData: false))
        XCTAssertFalse(QwenAPI.streamReset(of: CancellationError(), sawData: false))
    }
}
