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

    func testWindowProcessesAllItemsAndRespectsCancellation() async {
        var empty: [Int] = []
        await Offload.window(count: 0, limit: 2, work: { $0 }) { empty.append($0) }
        XCTAssertTrue(empty.isEmpty)

        var seen: [Int] = []
        await Offload.window(count: 5, limit: 2, work: { index in index * 2 }) { seen.append($0) }
        XCTAssertEqual(seen.sorted(), [0, 2, 4, 6, 8])

        let cancelledTask = Task { () -> Int in
            var received = 0
            await Offload.window(count: 6, limit: 2, work: { _ in
                try? await Task.sleep(for: .milliseconds(40))
                return 1
            }) { received += $0 }
            return received
        }
        try? await Task.sleep(for: .milliseconds(20))
        cancelledTask.cancel()
        let count = await cancelledTask.value
        XCTAssertLessThan(count, 6)
    }
}
