@testable import GwenMobileFeatureCore
import AVFoundation
import XCTest
import GwenMobileKit

@MainActor
private final class PlainAudioFeed: AudioFeeding {
    private(set) var voiceProcessing: Bool?

    var isRunning: Bool { false }

    func start(deliver: @escaping @Sendable (AVAudioPCMBuffer) -> Void) async throws {}

    func stop() {}
}

@MainActor
final class AudioFeedingDefaultTests: GwenTestCase {
    func testAFeedWithoutVoiceProcessingKeepsTheSilentDefault() async throws {
        let feed = PlainAudioFeed()
        try await feed.setVoiceProcessing(true)
        XCTAssertNil(feed.voiceProcessing, "wer den Echschutz nicht kann, schaltet ihn still nicht")
        XCTAssertFalse(feed.isVoiceProcessing)
    }
}
