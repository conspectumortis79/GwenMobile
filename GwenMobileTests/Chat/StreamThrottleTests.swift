@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

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

    func testFinishFlushesThePendingText() async throws {
        let sink = Sink()
        let throttle = StreamThrottle(interval: .milliseconds(20)) { sink.append($0) }
        throttle.receive("sofort")
        throttle.finish()
        XCTAssertEqual(sink.parts, ["sofort"])
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(sink.parts, ["sofort"])
    }

    func testFinishWithoutPendingTextKeepsWhatWasFlushed() async throws {
        let sink = Sink()
        let throttle = StreamThrottle(interval: .milliseconds(20)) { sink.append($0) }
        try await Task.sleep(for: .milliseconds(1))
        throttle.finish()
        XCTAssertEqual(sink.parts, [])
        throttle.receive("a")
        try await Task.sleep(for: .milliseconds(120))
        throttle.finish()
        XCTAssertEqual(sink.parts, ["a"])
    }
}
