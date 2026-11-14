@testable import GwenMobileFeatureCore
import GwenMobileKit
import XCTest

final class VideoAnalysisStoreTests: XCTestCase {
    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    private func writeSource(_ folder: URL, bytes: Int) throws -> URL {
        let url = folder.appendingPathComponent("source.mp4")
        try Data(repeating: 0x11, count: bytes).write(to: url)
        return url
    }

    private func store(_ folder: URL, calls: LockedValue<Int>,
                       output: @escaping @Sendable () -> Data) -> VideoAnalysisStore {
        VideoAnalysisStore(directory: folder.appendingPathComponent("cache")) { _, target in
            calls.mutate { $0 += 1 }
            try output().write(to: target)
        }
    }

    func testTheCompressedVariantIsCreatedOnceAndReused() async throws {
        let folder = try makeFolder()
        let source = try writeSource(folder, bytes: 4_000_000)
        let calls = LockedValue(0)
        let compressed = Data(repeating: 0x22, count: 1_000_000)
        let store = store(folder, calls: calls) { compressed }
        let first = await store.data(for: "doc_v.mp4", sourceURL: source)
        XCTAssertEqual(first, compressed)
        XCTAssertEqual(calls.current, 1)
        XCTAssertEqual(try Data(contentsOf: store.targetURL(for: "doc_v.mp4")), compressed)
        let second = await store.data(for: "doc_v.mp4", sourceURL: source)
        XCTAssertEqual(second, compressed)
        XCTAssertEqual(calls.current, 1)
    }

    func testAChangedSourceRebuildsTheCachedVariant() async throws {
        let folder = try makeFolder()
        let source = try writeSource(folder, bytes: 4_000_000)
        let calls = LockedValue(0)
        let first = Data(repeating: 0x22, count: 1_000_000)
        let second = Data(repeating: 0x33, count: 900_000)
        let output = LockedValue(first)
        let store = store(folder, calls: calls) { output.current }
        _ = await store.data(for: "doc_v.mp4", sourceURL: source)
        let target = store.targetURL(for: "doc_v.mp4")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)],
                                              ofItemAtPath: target.path)
        output.set(second)
        let rebuilt = await store.data(for: "doc_v.mp4", sourceURL: source)
        XCTAssertEqual(rebuilt, second)
        XCTAssertEqual(calls.current, 2)
    }

    func testConcurrentRequestsShareOneCompression() async throws {
        let folder = try makeFolder()
        let source = try writeSource(folder, bytes: 4_000_000)
        let calls = LockedValue(0)
        let compressed = Data(repeating: 0x22, count: 1_000_000)
        let store = VideoAnalysisStore(directory: folder.appendingPathComponent("cache")) { _, target in
            calls.mutate { $0 += 1 }
            try await Task.sleep(for: .milliseconds(100))
            try compressed.write(to: target)
        }
        async let first = store.data(for: "doc_v.mp4", sourceURL: source)
        async let second = store.data(for: "doc_v.mp4", sourceURL: source)
        let values = await [first, second]
        XCTAssertEqual(values, [compressed, compressed])
        XCTAssertEqual(calls.current, 1)
    }

    func testAFailedCompressionFallsBackToTheOriginal() async throws {
        let folder = try makeFolder()
        let source = try writeSource(folder, bytes: 4_000_000)
        let store = VideoAnalysisStore(directory: folder.appendingPathComponent("cache")) { _, _ in
            throw APIError(message: "kaputt")
        }
        let data = await store.data(for: "doc_v.mp4", sourceURL: source)
        XCTAssertEqual(data, try Data(contentsOf: source))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.targetURL(for: "doc_v.mp4").path))
    }

    func testASmallVideoIsLeftUntouched() async throws {
        let folder = try makeFolder()
        let source = try writeSource(folder, bytes: 1_000_000)
        let calls = LockedValue(0)
        let store = store(folder, calls: calls) { Data(repeating: 0x22, count: 100_000) }
        let data = await store.data(for: "doc_v.mp4", sourceURL: source)
        XCTAssertEqual(data, try Data(contentsOf: source))
        XCTAssertEqual(calls.current, 0)
    }

    func testAMissingSourceReturnsNothing() async throws {
        let folder = try makeFolder()
        let calls = LockedValue(0)
        let store = store(folder, calls: calls) { Data(repeating: 0x22, count: 100_000) }
        let data = await store.data(for: "doc_missing.mp4",
                                    sourceURL: folder.appendingPathComponent("missing.mp4"))
        XCTAssertNil(data)
        XCTAssertEqual(calls.current, 0)
    }

    func testPruneKeepsOnlyCachesWithAnExistingSource() async throws {
        let folder = try makeFolder()
        let source = try writeSource(folder, bytes: 4_000_000)
        let calls = LockedValue(0)
        let store = store(folder, calls: calls) { Data(repeating: 0x22, count: 1_000_000) }
        _ = await store.data(for: "doc_v.mp4", sourceURL: source)
        let target = store.targetURL(for: "doc_v.mp4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        store.prune(keeping: ["doc_v.mp4"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        try FileManager.default.removeItem(at: source)
        store.prune(keeping: [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }

    func testDiscardRemovesTheCachedVariant() async throws {
        let folder = try makeFolder()
        let source = try writeSource(folder, bytes: 4_000_000)
        let calls = LockedValue(0)
        let store = store(folder, calls: calls) { Data(repeating: 0x22, count: 1_000_000) }
        _ = await store.data(for: "doc_v.mp4", sourceURL: source)
        let target = store.targetURL(for: "doc_v.mp4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        store.discard(["doc_v.mp4"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }
}
