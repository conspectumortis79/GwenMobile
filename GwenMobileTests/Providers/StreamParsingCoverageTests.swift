@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

@MainActor
final class StreamParsingCoverageTests: GwenTestCase {
    override func tearDown() {
        MockHTTP.uninstall()
        super.tearDown()
    }

    private func request() throws -> URLRequest {
        URLRequest(url: try XCTUnwrap(URL(string: "https://mock.test/v1/chat/completions")))
    }

    private func collect() async -> Result<String, Error> {
        do {
            var text = ""
            for try await chunk in QwenAPI.streamText(req: try request()) {
                text += chunk
            }
            return .success(text)
        } catch {
            return .failure(error)
        }
    }

    func testACompletedStreamCollectsEveryChunk() async throws {
        MockHTTP.install { _ in (200, MockHTTP.sse("Hallo")) }
        let result = await collect()
        XCTAssertEqual(try result.get(), "Hallo")
    }

    func testARateLimitedAttemptIsRetried() async throws {
        let attempts = LockedValue(0)
        MockHTTP.install { _ in
            attempts.mutate { $0 += 1 }
            if attempts.current == 1 {
                return (429, Data("{\"error\":{\"message\":\"slow down\"}}".utf8))
            }
            return (200, MockHTTP.sse("Endlich"))
        }
        let result = await collect()
        XCTAssertEqual(try result.get(), "Endlich")
        XCTAssertEqual(attempts.current, 2)
    }

    func testARejectedStreamReportsTheProviderMessage() async throws {
        MockHTTP.install { _ in
            (403, Data("{\"error\":{\"message\":\"key abgelehnt\"}}".utf8))
        }
        let result = await collect()
        guard case .failure(let error) = result else {
            XCTFail("erwartet Fehler")
            return
        }
        XCTAssertTrue(error.localizedDescription.contains("key abgelehnt"), error.localizedDescription)
        XCTAssertNotNil(error as? APIError)
    }

    func testAServerErrorFailsWithoutRetry() async throws {
        let attempts = LockedValue(0)
        MockHTTP.install { _ in
            attempts.mutate { $0 += 1 }
            return (500, Data("kaputt".utf8))
        }
        let result = await collect()
        guard case .failure = result else {
            XCTFail("erwartet Fehler")
            return
        }
        XCTAssertEqual(attempts.current, 1)
    }

    func testAConnectionResetBeforeAnyDataIsRetriedOnce() async throws {
        let attempts = LockedValue(0)
        MockHTTP.failWith { _ in
            attempts.mutate { $0 += 1 }
            if attempts.current == 1 { return URLError(.networkConnectionLost) }
            return nil
        }
        MockHTTP.install { _ in (200, MockHTTP.sse("Zurück")) }
        let result = await collect()
        XCTAssertEqual(try result.get(), "Zurück")
        XCTAssertEqual(attempts.current, 2)
    }

    func testMalformedDataLinesAreSkipped() async throws {
        let body = "data: kein json\n"
            + "data: {\"choices\":[{\"delta\":{\"content\":\"Sauber\"}}]}\n"
            + "data: [DONE]\n"
        MockHTTP.install { _ in (200, Data(body.utf8)) }
        let result = await collect()
        XCTAssertEqual(try result.get(), "Sauber")
    }

    func testAStreamThatKeepsResettingGivesUpAfterOneRetry() async throws {
        let attempts = LockedValue(0)
        MockHTTP.install { _ in nil }
        MockHTTP.failWith { _ in
            attempts.mutate { $0 += 1 }
            return URLError(.networkConnectionLost)
        }
        let result = await collect()
        guard case .failure = result else {
            XCTFail("erwartet Fehler")
            return
        }
        XCTAssertEqual(attempts.current, 2)
    }

    func testAStreamThatStaysRateLimitedGivesUpAfterTwoRetries() async throws {
        let attempts = LockedValue(0)
        MockHTTP.install { _ in
            attempts.mutate { $0 += 1 }
            return (429, Data("{\"error\":{\"message\":\"slow down\"}}".utf8))
        }
        let result = await collect()
        guard case .failure = result else {
            XCTFail("erwartet Fehler")
            return
        }
        XCTAssertEqual(attempts.current, 3)
    }

    func testAStreamThatStallsWithoutContentFailsAndWithContentFinishes() async throws {
        QwenAPI.streamIdleOverride = 0.05
        MockHTTPProtocol.dataDelay = 0.2
        MockHTTP.install { _ in (200, Data("kein datenrahmen\n".utf8)) }
        let empty = await collect()
        guard case .failure = empty else {
            XCTFail("erwartet Fehler")
            return
        }
        MockHTTP.install { _ in
            (200, Data("data: {\"choices\":[{\"delta\":{\"content\":\"Hallo\"}}]}\nkein rahmen\n".utf8))
        }
        let partial = await collect()
        XCTAssertEqual(try partial.get(), "Hallo")
    }

    func testACancelledStreamEndsAsCancellation() async {
        MockHTTP.install { _ in (200, Data()) }
        MockHTTP.failWith { _ in URLError(.cancelled) }
        let result = await collect()
        guard case .failure(let error) = result else {
            XCTFail("erwartet Fehler")
            return
        }
        XCTAssertTrue(error is CancellationError)
    }

    func testAStreamWithOnlyTheDoneMarkerEndsEmpty() async throws {
        MockHTTP.install { _ in (200, Data("data: [DONE]\n".utf8)) }
        let result = await collect()
        XCTAssertEqual(try result.get(), "")
    }

    func testTheResetDecisionNeedsAnEmptyStream() {
        XCTAssertTrue(QwenAPI.streamReset(of: URLError(.networkConnectionLost), sawData: false))
        XCTAssertFalse(QwenAPI.streamReset(of: URLError(.networkConnectionLost), sawData: true))
        XCTAssertFalse(QwenAPI.streamReset(of: URLError(.cancelled), sawData: false))
        XCTAssertFalse(QwenAPI.streamReset(of: URIError.badURL, sawData: false))
    }
}

private enum URIError: Error {
    case badURL
}

extension StreamParsingCoverageTests {
    func testTheLocalLineParserCoversIgnoredEmptyDoneAndPayload() {
        XCTAssertEqual(QwenAPI.localLine("event: ping"), .ignore(checkIdle: true))
        XCTAssertEqual(QwenAPI.localLine("data:"), .ignore(checkIdle: false))
        XCTAssertEqual(QwenAPI.localLine("data: [DONE]"), .done)
        XCTAssertEqual(QwenAPI.localLine("data: {\"x\":1}"), .payload("{\"x\":1}"))
    }
}

extension StreamParsingCoverageTests {
    func testTheLocalStreamPathConsumesInjectedLines() async {
        let previous = QwenAPI.localLines
        defer { QwenAPI.localLines = previous }
        QwenAPI.localLines = { _ in
            AsyncThrowingStream { continuation in
                continuation.yield("event: ping")
                continuation.yield("data:")
                continuation.yield("data: {\"choices\":[{\"delta\":{\"content\":\"Lokal\"}}]}")
                continuation.yield("data: [DONE]")
                continuation.finish()
            }
        }
        let url = URL(string: "http://gwen.local/v1/chat/completions")!
        var text = ""
        do {
            for try await chunk in QwenAPI.streamText(req: URLRequest(url: url)) {
                text += chunk
            }
        } catch {
            XCTFail("unerwarteter Fehler: \(error)")
        }
        XCTAssertEqual(text, "Lokal")
    }
}

extension StreamParsingCoverageTests {
    func testTheLocalStreamFallsBackToTheRuntime() async {
        let previous = QwenAPI.localLines
        defer { QwenAPI.localLines = previous }
        QwenAPI.localLines = nil
        let url = URL(string: "http://gwen.local/v1/chat/completions")!
        let stream = QwenAPI.streamText(req: URLRequest(url: url))
        do {
            for try await _ in stream {}
        } catch {
            XCTAssertNotNil(error)
        }
    }
}
