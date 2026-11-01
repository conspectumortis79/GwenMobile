@testable import GwenMobileDevice
import XCTest
import GwenMobileKit

@MainActor
final class AppGapTests: GwenTestCase {
    func testSmokeTheAppURLHandling() {
        URLOpenSpy.install()
        defer { URLOpenSpy.uninstall() }
        let app = GwenMobileApp()
        app.handle(URL(string: "gwenmobile://listen")!)
        app.handle(URL(string: "gwenmobile://test/scanwet")!)
        app.handle(URL(string: "https://open.spotify.com/track/abc")!)
        app.handle(URL(string: "https://example.com/ohne")!)
    }

    func testTheTraceSinkWritesFiles() throws {
        _ = TraceSink.enabled
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gap-trace.txt")
        try? FileManager.default.removeItem(at: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let sink = TraceSink(url: url)
        sink.mark("test")
        sink.append("zeile")
        let expectation = expectation(description: "trace")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { expectation.fulfill() }
        wait(for: [expectation], timeout: 3)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testTheAssertionActionsAndFailures() {
        let failure = AssertionFailure(site: "site", file: "Datei.m", line: 7, message: "kaputt")
        XCTAssertEqual(failure.reason, "site Datei.m:7 kaputt")
        XCTAssertTrue(failure.raisedIn("Datei.m"))
        XCTAssertFalse(failure.raisedIn("Andere.m"))
        AssertionShieldActions.suppress(failure)
        AssertionShieldActions.raise = { _ in }
        AssertionShieldActions.escalate(failure)
        AssertionShieldActions.raise = { value in NSException(assertion: value).raise() }
        _ = AssertionFailure.method(NSSelectorFromString("description"), object: nil,
                                    file: "Datei.m", lineNumber: 7, description: nil)
        _ = AssertionFailure.function("funktion", file: nil, lineNumber: 3, description: "text")
        _ = AssertionFailure.function(nil, file: nil, lineNumber: 3, description: nil)
        _ = AssertionFailure.method(NSSelectorFromString("description"), object: NSObject(),
                                    file: nil, lineNumber: 1, description: "x")
        let shield = ScrollAssertionShield.handler()
        _ = shield
    }
}
