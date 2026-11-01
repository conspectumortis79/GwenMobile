@testable import GwenMobileFeatureCore
import XCTest
import GwenMobileKit

final class RunStopTests: GwenTestCase {
    func testCancellationErrorsAreRecognised() {
        XCTAssertTrue(RunStop.isCancellation(CancellationError()))
        XCTAssertTrue(RunStop.isCancellation(URLError(.cancelled)))
        XCTAssertFalse(RunStop.isCancellation(URLError(.timedOut)))
        XCTAssertFalse(RunStop.isCancellation(APIError(message: "HTTP 500")))
    }

    func testInsideACancelledRunEveryErrorCountsAsACancellation() async {
        let cancelled = Task { () -> Bool in
            while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(10)) }
            return RunStop.isCancellation(URLError(.timedOut))
        }
        cancelled.cancel()
        let recognised = await cancelled.value
        XCTAssertTrue(recognised, "ein gestoppter Lauf darf keinen Fehler mehr melden")
    }

    func testInsideACancelledMainActorRunTheWrappedAPIErrorIsRecognised() async {
        let cancelled = Task { @MainActor () -> (Bool, Bool) in
            while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(10)) }
            let wrapped = APIError(message: "Abgebrochen", recoveredText: "ein halber Satz")
            return (RunStop.isCancellation(wrapped), Task.isCancelled)
        }
        cancelled.cancel()
        let (recognised, flag) = await cancelled.value
        XCTAssertTrue(flag, "der Lauf muss als abgebrochen gelten")
        XCTAssertTrue(recognised, "auch ein in APIError verpackter Abbruch muss erkannt werden")
    }
}
