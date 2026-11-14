import XCTest
import GwenMobileKit

final class OffloadTests: XCTestCase {
    func testTheResultOfTheDetachedWorkArrivesAtTheCaller() async throws {
        let answer = try await Offload.run { "fertig" }
        XCTAssertEqual(answer, "fertig")
    }

    func testACancelledCallerEndsTheDetachedWork() async throws {
        let finished = LockedValue(false)
        let task = Task { () -> String in
            try await Offload.run {
                try await Task.sleep(for: .seconds(2))
                finished.set(true)
                return "zu spät"
            }
        }
        try await Task.sleep(for: .milliseconds(120))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Abbruch hätte geworfen werden müssen")
        } catch is CancellationError {
            XCTAssertTrue(task.isCancelled)
        } catch let error as URLError {
            XCTAssertEqual(error.code, .cancelled)
        } catch {
            XCTFail("unerwarteter Fehler: \(error)")
        }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(finished.current, "die abgelöste Arbeit lief trotz Abbruchs weiter")
    }

    func testAnErrorOfTheWorkedTaskReachesTheCallerUnchanged() async {
        do {
            _ = try await Offload.run { throw APIError(message: "Innenfehler") }
            XCTFail("Fehler hätte ankommen müssen")
        } catch let error as APIError {
            XCTAssertEqual(error.message, "Innenfehler")
        } catch {
            XCTFail("unerwarteter Fehler: \(error)")
        }
    }

    func testOrNilFlatKeepsAValueAndSwallowsAnError() async {
        let answer = await Offload.orNilFlat { "kurz" }
        XCTAssertEqual(answer, "kurz")
        let empty = await Offload.orNilFlat { () -> String? in nil }
        XCTAssertNil(empty)
        let failed = await Offload.orNilFlat { () -> String? in throw APIError(message: "egal") }
        XCTAssertNil(failed)
    }
}
