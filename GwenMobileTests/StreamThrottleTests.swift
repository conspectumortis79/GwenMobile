import XCTest
@testable import GwenMobile

@MainActor
final class StreamThrottleTests: XCTestCase {
    private final class Sink {
        var parts: [String] = []
        func append(_ text: String) { parts.append(text) }
    }

    func testChunksAreMergedIntoOneFlushPerWindow() async throws {
        let sink = Sink()
        let throttle = StreamThrottle(interval: .milliseconds(20)) { sink.append($0) }
        throttle.receive("a")
        throttle.receive("b")
        throttle.receive("c")
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(sink.parts, ["abc"])
    }

    func testLaterChunksStartANewWindow() async throws {
        let sink = Sink()
        let throttle = StreamThrottle(interval: .milliseconds(20)) { sink.append($0) }
        throttle.receive("x")
        try await Task.sleep(for: .milliseconds(120))
        throttle.receive("y")
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(sink.parts, ["x", "y"])
    }

    func testCancelDropsPendingText() async throws {
        let sink = Sink()
        let throttle = StreamThrottle(interval: .milliseconds(20)) { sink.append($0) }
        throttle.receive("nichts")
        throttle.cancel()
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(sink.parts, [])
    }
}
