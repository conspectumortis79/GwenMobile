@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import AVFoundation
import XCTest
import GwenMobileKit

@MainActor
final class MicrophoneTapTests: GwenTestCase {
    func testTheTapStaysIdleUntilStarted() async {
        let tap = MicrophoneTap()
        XCTAssertFalse(tap.isFlowing)
        tap.stop()
        do { try await tap.resume() } catch {}
        do { try await tap.reconnect() } catch {}
        XCTAssertFalse(tap.isFlowing)
    }

    func testTheStubAcceptsTheVoiceProcessingSwitch() async throws {
        let tap = StubAudioTap()
        XCTAssertFalse(tap.isVoiceProcessing)
        try await tap.setVoiceProcessing(true)
        try await tap.setVoiceProcessing(false)
    }

    func testThePreferredSetupsAreOrderedAndLabelled() {
        XCTAssertFalse(RecordingSetup.preferred.isEmpty)
        for setup in RecordingSetup.preferred {
            XCTAssertFalse(setup.label.isEmpty)
        }
    }
}
