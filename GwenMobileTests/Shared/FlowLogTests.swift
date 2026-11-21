@testable import GwenMobileKit
import XCTest

final class FlowLogTests: XCTestCase {
    func testTheTraceSinkSurvivesAWriteFailure() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("flowlog-failing-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("trace.txt")
        try? Data("start".utf8).write(to: url)
        let sink = TraceSink(url: url, writer: { _, _ in throw CocoaError(.fileWriteUnknown) })
        sink.append("erster Versuch")
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        try? FileManager.default.removeItem(at: root)
    }

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
