import GwenMobileKit
import XCTest

final class FlowLogTests: XCTestCase {
    func testTheTraceSinkSurvivesAMissingDirectory() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowlog-missing-\(UUID().uuidString)")
        let url = root.appendingPathComponent("trace.txt")
        let sink = TraceSink(url: url)
        sink.append("erster Versuch")
        sink.mark("zweiter Versuch")
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
