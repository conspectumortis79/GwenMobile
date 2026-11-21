@testable import GwenMobileFeatureCore
import AVFoundation
import UIKit
import XCTest
import GwenMobileKit

@MainActor
final class AudioWatcherAndIntentCoverageTests: GwenTestCase {
    func testTheWatcherForwardsEveryNotification() async throws {
        let watcher = AudioDisruptionWatcher()
        let seen = LockedValue<[AudioDisruption]>([])
        watcher.start { disruption in seen.mutate { $0.append(disruption) } }
        let center = NotificationCenter.default
        center.post(name: AVAudioSession.interruptionNotification, object: nil,
                    userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(seen.current, [.began])
        center.post(name: AVAudioSession.interruptionNotification, object: nil,
                    userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue])
        center.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        center.post(name: .AVAudioEngineConfigurationChange, object: nil)
        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        center.post(name: AVAudioSession.routeChangeNotification, object: nil,
                    userInfo: [AVAudioSessionRouteChangeReasonKey:
                                AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(seen.current.contains(.ended))
        XCTAssertTrue(seen.current.contains(.reconfigured))
        XCTAssertEqual(AudioDisruption.interruption(nil), nil)
        XCTAssertEqual(AudioDisruption.interruption(UInt.max), nil)
        watcher.stop()
    }

    func testAListenRequestRaisesTheToken() {
        let before = ListenRequests.shared.token
        ListenRequests.shared.ask(from: "test")
        XCTAssertEqual(ListenRequests.shared.token, before + 1)
    }

    func testTheSpeechSynthesizerHelpers() async {
        let synthesizer = SpeechSynthesizer()
        synthesizer.speak(text: "   ")
        synthesizer.stop()
        XCTAssertNotNil(VoiceCatalog.options(for: .de))
    }
}
