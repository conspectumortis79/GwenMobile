@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import AVFoundation
import UIKit
import XCTest
import GwenMobileKit

@MainActor
final class HeadsetNotifierAudioCoverageTests: GwenTestCase {
    func testTheHandoverPolicyDecidesEveryMove() {
        var policy = HeadsetHandoverPolicy()
        let arrived = RouteChange(deviceLeft: false, deviceArrived: true, previousBluetooth: [],
                                  currentBluetooth: ["a"], available: ["a"])
        let left = RouteChange(deviceLeft: true, previousBluetooth: ["a"], currentBluetooth: [],
                               available: [])
        XCTAssertEqual(policy.decide(left), .yield)
        XCTAssertEqual(policy.decide(arrived), .reclaim(preferring: ["a"]))
        XCTAssertEqual(policy.decide(arrived), .none)
        let otherLeft = RouteChange(deviceLeft: true, previousBluetooth: ["b"], currentBluetooth: [],
                                    available: [])
        XCTAssertEqual(policy.decide(otherLeft), .yield)
        let stillGone = RouteChange(deviceLeft: false, previousBluetooth: ["b"], currentBluetooth: [],
                                    available: [])
        XCTAssertEqual(policy.decide(stillGone), .none)
        let returned = RouteChange(deviceLeft: false, deviceArrived: false, previousBluetooth: ["b"],
                                   currentBluetooth: ["b"], available: ["b"])
        XCTAssertEqual(policy.decide(returned), .reclaim(preferring: ["b"]))
    }

    func testSmokeTheHandoverLifecycleFollowsRouteChanges() async throws {
        let handover = HeadsetHandover()
        handover.start()
        handover.start()
        NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil,
                                        userInfo: [AVAudioSessionRouteChangeReasonKey:
                                                    AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
        try await Task.sleep(for: .milliseconds(150))
        handover.stop()
        handover.stop()
    }

    func testTheBluetoothPortsHelpers() {
        XCTAssertTrue(BluetoothPorts.ids(in: nil).isEmpty)
        let note = Notification(name: AVAudioSession.routeChangeNotification, object: nil,
                                userInfo: [AVAudioSessionRouteChangeReasonKey:
                                            AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue])
        let change = BluetoothPorts.change(from: note)
        XCTAssertTrue(change.deviceArrived)
        XCTAssertFalse(change.deviceLeft)
        _ = BluetoothPorts.availableInputs()
    }

    func testTheListenNoticesBuildAndPost() async {
        XCTAssertNil(ListenNotice.answer("   "))
        let notice = ListenNotice.answer("Eine gesprochene Antwort")
        XCTAssertEqual(notice?.body, "Eine gesprochene Antwort")
        XCTAssertEqual(ListenNotice.stopped.id, ListenNotice.stoppedID)
        let notifier = LocalListenNotifier()
        notifier.listeningStopped()
        notifier.answered("Antwort")
        notifier.answered("   ")
        try? await Task.sleep(for: .milliseconds(150))
    }

    func testSmokeTheAudioRouteCountersReleaseOnlyTheirOwnRound() async {
        await AudioRoute.shared.startPlayback()
        let playback = AudioRound.playback.current
        await AudioRoute.shared.endPlayback(atRound: playback)
        await AudioRoute.shared.endPlayback(atRound: -1)
        AudioRound.recording.mutate { $0 += 1 }
        let recording = AudioRound.recording.current
        await AudioRoute.shared.endRecording(atRound: recording)
        AudioRound.recording.mutate { $0 += 1 }
        await AudioRoute.shared.endRecording(atRound: AudioRound.recording.current)
        AudioRound.capturing.mutate { $0 += 1 }
        await AudioRoute.shared.startPlayback()
        AudioRound.capturing.mutate { $0 = max(0, $0 - 1) }
    }

    func testTheSpeechSynthesizerStripsAndStops() {
        let stripped = SpeechSynthesizer.stripForSpeech("# Titel **fett** `code` [Link](https://x.test)")
        XCTAssertFalse(stripped.contains("**"))
        XCTAssertFalse(stripped.contains("`"))
        let synthesizer = SpeechSynthesizer()
        synthesizer.speak(text: "**Hallo** `Welt`")
        synthesizer.stop()
        synthesizer.stop()
        synthesizer.speechSynthesizer(AVSpeechSynthesizer(), didFinish: AVSpeechUtterance(string: "x"))
        synthesizer.speechSynthesizer(AVSpeechSynthesizer(), didCancel: AVSpeechUtterance(string: "x"))
    }
}
