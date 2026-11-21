@testable import GwenMobileFeatureCore
import GwenMobileKit
import XCTest

final class VideoAnalysisStoreTests: XCTestCase {
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
        let folder = try temporaryFolder()
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

    func testTheDefaultCompressionRunsForAnUnreadableVideo() async throws {
        let folder = try temporaryFolder()
        let source = try writeSource(folder, bytes: 4_000_000)
        let store = VideoAnalysisStore(directory: folder.appendingPathComponent("cache"))
        let data = await store.data(for: "doc_v.mp4", sourceURL: source)
        XCTAssertEqual(data?.count, 4_000_000)
    }

    func testAChangedSourceRebuildsTheCachedVariant() async throws {
        let folder = try temporaryFolder()
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
        let folder = try temporaryFolder()
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

    func testDiscardingCancelsARunningCompression() async throws {
        let folder = try temporaryFolder()
        let source = try writeSource(folder, bytes: 4_000_000)
        let started = LockedValue(false)
        let release = LockedValue(false)
        let cache = folder.appendingPathComponent("cache")
        let store = VideoAnalysisStore(directory: cache) { _, target in
            started.set(true)
            while !release.current {
                try? await Task.sleep(for: .milliseconds(5))
            }
            try Data(repeating: 0x22, count: 1_000_000).write(to: target)
        }
        let expected = store.targetURL(for: "doc_v.mp4")
        let task = Task { await store.data(for: "doc_v.mp4", sourceURL: source) }
        defer { release.set(true) }
        var waited = 0
        while !started.current, waited < 200 {
            try await Task.sleep(for: .milliseconds(5))
            waited += 1
        }
        XCTAssertTrue(started.current)
        store.discard(["doc_v.mp4"])
        release.set(true)
        _ = await task.value
        XCTAssertFalse(FileManager.default.fileExists(atPath: expected.path))
    }

    func testAFailedCompressionFallsBackToTheOriginal() async throws {
        let folder = try temporaryFolder()
        let source = try writeSource(folder, bytes: 4_000_000)
        let store = VideoAnalysisStore(directory: folder.appendingPathComponent("cache")) { _, _ in
            throw APIError(message: "kaputt")
        }
        let data = await store.data(for: "doc_v.mp4", sourceURL: source)
        XCTAssertEqual(data, try Data(contentsOf: source))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.targetURL(for: "doc_v.mp4").path))
    }

    func testAFailedCompressionIsNotRepeatedUntilTheStoreIsCreatedAgain() async throws {
        let folder = try temporaryFolder()
        let source = try writeSource(folder, bytes: 4_000_000)
        let original = try Data(contentsOf: source)
        let calls = LockedValue(0)
        let failing: @Sendable (URL, URL) async throws -> Void = { _, _ in
            calls.mutate { $0 += 1 }
            throw APIError(message: "kaputt")
        }
        let cache = folder.appendingPathComponent("cache")
        let store = VideoAnalysisStore(directory: cache, compress: failing)
        for _ in 0..<3 {
            let data = await store.data(for: "doc_v.mp4", sourceURL: source)
            XCTAssertEqual(data, original)
        }
        XCTAssertEqual(calls.current, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.originalMarkURL(for: "doc_v.mp4").path))
        let relaunched = VideoAnalysisStore(directory: cache, compress: failing)
        _ = await relaunched.data(for: "doc_v.mp4", sourceURL: source)
        XCTAssertEqual(calls.current, 2)
    }

    func testAnEmptyExportCountsAsAFailedCompression() async throws {
        let folder = try temporaryFolder()
        let source = try writeSource(folder, bytes: 4_000_000)
        let calls = LockedValue(0)
        let store = store(folder, calls: calls) { Data() }
        for _ in 0..<2 {
            let data = await store.data(for: "doc_v.mp4", sourceURL: source)
            XCTAssertEqual(data, try Data(contentsOf: source))
        }
        XCTAssertEqual(calls.current, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.originalMarkURL(for: "doc_v.mp4").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.targetURL(for: "doc_v.mp4").path))
    }

    func testAVideoThatDoesNotShrinkIsExportedOnlyOnce() async throws {
        let folder = try temporaryFolder()
        let source = try writeSource(folder, bytes: 4_000_000)
        let original = try Data(contentsOf: source)
        let calls = LockedValue(0)
        let store = store(folder, calls: calls) { Data(repeating: 0x22, count: 4_500_000) }
        for _ in 0..<3 {
            let data = await store.data(for: "doc_v.mp4", sourceURL: source)
            XCTAssertEqual(data, original)
        }
        XCTAssertEqual(calls.current, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.originalMarkURL(for: "doc_v.mp4").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.targetURL(for: "doc_v.mp4").path))
    }

    func testTheDecisionForTheOriginalSurvivesANewStore() async throws {
        let folder = try temporaryFolder()
        let source = try writeSource(folder, bytes: 4_000_000)
        let calls = LockedValue(0)
        let first = store(folder, calls: calls) { Data(repeating: 0x22, count: 4_000_000) }
        _ = await first.data(for: "doc_v.mp4", sourceURL: source)
        XCTAssertEqual(calls.current, 1)
        let relaunched = store(folder, calls: calls) { Data(repeating: 0x22, count: 4_000_000) }
        let data = await relaunched.data(for: "doc_v.mp4", sourceURL: source)
        XCTAssertEqual(data, try Data(contentsOf: source))
        XCTAssertEqual(calls.current, 1)
    }

    func testAChangedSourceIsCompressedAgainAfterTheOriginalWasKept() async throws {
        let folder = try temporaryFolder()
        let source = try writeSource(folder, bytes: 4_000_000)
        let calls = LockedValue(0)
        let output = LockedValue(Data(repeating: 0x22, count: 4_500_000))
        let store = store(folder, calls: calls) { output.current }
        _ = await store.data(for: "doc_v.mp4", sourceURL: source)
        let mark = store.originalMarkURL(for: "doc_v.mp4")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)],
                                              ofItemAtPath: mark.path)
        let smaller = Data(repeating: 0x33, count: 900_000)
        output.set(smaller)
        let rebuilt = await store.data(for: "doc_v.mp4", sourceURL: source)
        XCTAssertEqual(rebuilt, smaller)
        XCTAssertEqual(calls.current, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: mark.path))
    }

    func testASmallVideoIsLeftUntouched() async throws {
        let folder = try temporaryFolder()
        let source = try writeSource(folder, bytes: 1_000_000)
        let calls = LockedValue(0)
        let store = store(folder, calls: calls) { Data(repeating: 0x22, count: 100_000) }
        let data = await store.data(for: "doc_v.mp4", sourceURL: source)
        XCTAssertEqual(data, try Data(contentsOf: source))
        XCTAssertEqual(calls.current, 0)
    }

    func testAMissingSourceReturnsNothing() async throws {
        let folder = try temporaryFolder()
        let calls = LockedValue(0)
        let store = store(folder, calls: calls) { Data(repeating: 0x22, count: 100_000) }
        let data = await store.data(for: "doc_missing.mp4",
                                    sourceURL: folder.appendingPathComponent("missing.mp4"))
        XCTAssertNil(data)
        XCTAssertEqual(calls.current, 0)
    }

    func testPruneKeepsOnlyCachesWithAnExistingSource() async throws {
        let folder = try temporaryFolder()
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

    func testPruneDropsOrphanedMarksAndLeftoverExportsButNothingElse() async throws {
        let folder = try temporaryFolder()
        let source = try writeSource(folder, bytes: 4_000_000)
        let calls = LockedValue(0)
        let store = store(folder, calls: calls) { Data(repeating: 0x22, count: 4_500_000) }
        _ = await store.data(for: "doc_v.mp4", sourceURL: source)
        let mark = store.originalMarkURL(for: "doc_v.mp4")
        let cache = folder.appendingPathComponent("cache")
        let leftover = cache.appendingPathComponent("tmp_abgebrochen.mp4")
        let foreign = cache.appendingPathComponent("notiz.txt")
        try Data(repeating: 0x44, count: 10).write(to: leftover)
        try Data(repeating: 0x55, count: 10).write(to: foreign)
        store.prune(keeping: ["doc_v.mp4"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: mark.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: leftover.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: foreign.path))
        store.prune(keeping: [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: mark.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: foreign.path))
    }

    func testCacheNamesLeadBackToTheirSource() {
        XCTAssertEqual(VideoAnalysisStore.sourceName(ofCached: VideoAnalysisStore.analysisName(for: "doc_v.mp4")),
                       "doc_v.mp4")
        XCTAssertEqual(VideoAnalysisStore.sourceName(ofCached: VideoAnalysisStore.originalMarkName(for: "doc_v.mp4")),
                       "doc_v.mp4")
        XCTAssertNil(VideoAnalysisStore.sourceName(ofCached: "tmp_abgebrochen.mp4"))
        XCTAssertNil(VideoAnalysisStore.sourceName(ofCached: "notiz.txt"))
    }

    func testDiscardRemovesTheCachedVariant() async throws {
        let folder = try temporaryFolder()
        let source = try writeSource(folder, bytes: 4_000_000)
        let calls = LockedValue(0)
        let store = store(folder, calls: calls) { Data(repeating: 0x22, count: 1_000_000) }
        _ = await store.data(for: "doc_v.mp4", sourceURL: source)
        let target = store.targetURL(for: "doc_v.mp4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        store.discard(["doc_v.mp4"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }

    func testDiscardForgetsAKeptOriginalAndAFailedAttempt() async throws {
        let folder = try temporaryFolder()
        let source = try writeSource(folder, bytes: 4_000_000)
        let calls = LockedValue(0)
        let kept = store(folder, calls: calls) { Data(repeating: 0x22, count: 4_500_000) }
        _ = await kept.data(for: "doc_v.mp4", sourceURL: source)
        let mark = kept.originalMarkURL(for: "doc_v.mp4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: mark.path))
        kept.discard(["doc_v.mp4"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: mark.path))
        let failures = LockedValue(0)
        let failing = VideoAnalysisStore(directory: folder.appendingPathComponent("failing")) { _, _ in
            failures.mutate { $0 += 1 }
            throw APIError(message: "kaputt")
        }
        _ = await failing.data(for: "doc_v.mp4", sourceURL: source)
        failing.discard(["doc_v.mp4"])
        _ = await failing.data(for: "doc_v.mp4", sourceURL: source)
        XCTAssertEqual(failures.current, 2)
    }

    func testPruningKeepsActiveTemporaryFileWhileRemovingStaleOnes() async throws {
        let folder = try temporaryFolder()
        let source = try writeSource(folder, bytes: 4_000_000)
        let cache = folder.appendingPathComponent("cache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let stale = cache.appendingPathComponent("tmp_stale.mp4")
        try Data([1, 2, 3]).write(to: stale)
        let started = LockedValue(false)
        let release = LockedValue(false)
        let activeTemp = LockedValue<URL?>(nil)
        let store = VideoAnalysisStore(directory: cache) { _, target in
            try Data(repeating: 0x22, count: 1_000_000).write(to: target)
            activeTemp.set(target)
            started.set(true)
            while !release.current {
                try? await Task.sleep(for: .milliseconds(5))
            }
        }
        let task = Task { await store.data(for: "doc_v.mp4", sourceURL: source) }
        defer { release.set(true) }
        var waited = 0
        while !started.current, waited < 200 {
            try await Task.sleep(for: .milliseconds(5))
            waited += 1
        }
        let active = try XCTUnwrap(activeTemp.current)
        store.prune(keeping: ["doc_v.mp4"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: active.path))
        release.set(true)
        let result = await task.value
        XCTAssertEqual(result?.count, 1_000_000)
    }
}
