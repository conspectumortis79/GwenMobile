@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit

@MainActor
final class VideoCompressionRouteTests: GwenTestCase {
    private let hosted = HostedChatView()

    override func setUp() {
        super.setUp()
        MockHTTP.install(MockHTTP.defaultHandler)
    }

    override func tearDown() async throws {
        MockHTTP.uninstall()
        hosted.close()
        try await super.tearDown()
    }

    func testTheRouteHandsTheCompressedVideoToTheTurn() async throws {
        let paths = temporaryPaths("video-compression-route")
        let compressed = Data(repeating: 0x42, count: 700_000)
        let calls = LockedValue(0)
        let analysis = VideoAnalysisStore(directory: paths.videoAnalysis) { _, target in
            calls.mutate { $0 += 1 }
            try compressed.write(to: target)
        }
        let documents = DocumentStore(paths: paths, videoAnalysis: analysis)
        let store = HostedChatView.store(paths, documents: documents)
        let savedProvider = AppSettings.shared.provider
        let savedProfile = AppSettings.shared.profile(of: .qwenCloud)
        defer {
            AppSettings.shared.provider = savedProvider
            AppSettings.shared.profiles[.qwenCloud] = savedProfile
        }
        AppSettings.shared.provider = .qwenCloud
        AppSettings.shared.videoModel = "test-video-model"
        let view = try await hosted.open(store, in: self)
        let source = try XCTUnwrap(documents.store(data: Data(repeating: 0x11, count: 4_000_000),
                                                   fileExtension: "mp4"))
        let pending = PendingFile(name: "clip.mp4", kind: .video, file: source.file, bytes: source.bytes)
        let text = DropPrompt.text(pictures: 0, files: 0, videos: 1)
        let routed = await view.route(text: text, pictures: [], files: [pending])
        XCTAssertEqual(calls.current, 1)
        XCTAssertEqual(routed?.turn.videoFiles, [source.file])
        XCTAssertEqual(routed?.turn.videos, [compressed])
        let repeated = await view.route(text: text, pictures: [], files: [pending])
        XCTAssertEqual(calls.current, 1)
        XCTAssertEqual(repeated?.turn.videos, [compressed])
        let target = analysis.targetURL(for: source.file)
        try FileManager.default.removeItem(at: source.url)
        documents.pruneAnalysisCache()
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }
}
