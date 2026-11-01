@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import AVFoundation
import Speech
import XCTest
import GwenMobileKit

@MainActor
final class VoiceLogicGapTests: GwenTestCase {
    func testTheChimeAndCuePlayers() {
        ChimePlayer(tone: .sent).play()
        let missing = ChosenCue(chosen: { "gibt-es-nicht" }, chime: ChimePlayer(tone: .sent))
        missing.play()
        let empty = ChosenCue(chosen: { "" }, chime: ChimePlayer(tone: .sent))
        empty.play()
        let preview = CuePreview(tone: .sent)
        preview.play("")
        preview.play("gibt-es-nicht")
        let player = SoundFilePlayer()
        XCTAssertFalse(player.play(path: "gibt-es-nicht"))
    }

    func testSmokeTheAudioRouteRelease() async {
        await AudioRoute.shared.endPlayback(atRound: AudioRound.playback.current)
        await AudioRoute.shared.endRecording(atRound: AudioRound.recording.current)
        await AudioRoute.shared.startPlayback()
        await AudioRoute.shared.endPlayback(atRound: AudioRound.playback.current)
        await AudioRoute.shared.startPlayback()
        await AudioRoute.shared.endRecording(atRound: AudioRound.recording.current)
        await AudioRoute.shared.endPlayback(atRound: AudioRound.playback.current)
        await AudioRoute.shared.endPlayback(atRound: 999)
        await AudioRoute.shared.endRecording(atRound: 999)
    }

    func testTheMicrophoneTapFailurePaths() async {
        let tap = MicrophoneTap()
        tap.prepareSession = { _ in }
        try? await tap.start { _ in }
        XCTAssertFalse(tap.isFlowing)
        tap.stop()
        try? await tap.resume()
        try? await tap.reconnect()
        let failing = MicrophoneTap()
        failing.prepareSession = { _ in throw APIError(message: "keine sitzung") }
        do {
            try await failing.start { _ in }
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        failing.stop()
    }

    func testSmokeTheSpeechSynthesizerStops() async {
        let speech = SpeechSynthesizer()
        speech.speak(text: "Hallo Welt", voiceIdentifier: VoiceOption.systemDefaultID)
        try? await Task.sleep(for: .milliseconds(300))
        speech.stop()
        speech.speak(text: "   ")
        speech.stop()
        speech.speak(text: "Noch ein Satz")
        try? await Task.sleep(for: .seconds(2))
        speech.stop()
    }

    func testSmokeTheSpeechSynthesizerReleasesTheRoundAfterAStopDuringStart() async {
        AudioRoute.playbackDelay = .milliseconds(300)
        defer { AudioRoute.playbackDelay = nil }
        let speech = SpeechSynthesizer()
        speech.speak(text: "Hallo Welt", voiceIdentifier: VoiceOption.systemDefaultID)
        try? await Task.sleep(for: .milliseconds(50))
        speech.stop()
        try? await Task.sleep(for: .milliseconds(400))
    }

    func testSmokeTheHeadsetHandoverStartsAndStops() {
        let handover = HeadsetHandover()
        handover.start()
        handover.start()
        NotificationCenter.default.post(
            name: AVAudioSession.routeChangeNotification, object: nil,
            userInfo: [AVAudioSessionRouteChangeReasonKey:
                        AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
        handover.stop()
        handover.stop()
    }
}

private final class FakeAudioEngine: AudioEngineing, @unchecked Sendable {
    var isEngineRunning = false
    var format: AVAudioFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    var failure: Error?
    var tap: AVAudioNodeTapBlock?
    private(set) var installed = 0
    private(set) var removed = 0
    private(set) var duplicates = 0
    private(set) var voiceProcessing = false

    func inputFormat() -> AVAudioFormat { format }

    func installTap(bufferSize: AVAudioFrameCount, format: AVAudioFormat,
                    block: @escaping AVAudioNodeTapBlock) {
        if tap != nil { duplicates += 1 }
        installed += 1
        tap = block
    }

    func removeTap() {
        removed += 1
        tap = nil
    }

    func prepare() {}

    func start() throws {
        if let failure { throw failure }
        isEngineRunning = true
    }

    func stop() { isEngineRunning = false }

    func setVoiceProcessingEnabled(_ enabled: Bool) throws {
        voiceProcessing = enabled
    }
}

@MainActor
extension VoiceLogicGapTests {
    func testTheMicrophoneTapEnablesVoiceProcessingForTheConversation() async throws {
        let engine = FakeAudioEngine()
        let setup = RecordingSetup(label: "probe", mode: .measurement, options: [])
        let tap = MicrophoneTap(setups: [setup], engine: engine)
        tap.prepareSession = { _ in }
        try await tap.setVoiceProcessing(true)
        XCTAssertTrue(tap.voiceProcessing)
        XCTAssertTrue(tap.isVoiceProcessing)
        try await tap.start { _ in }
        XCTAssertTrue(engine.voiceProcessing)
        XCTAssertEqual(engine.installed, 1)
        try await tap.setVoiceProcessing(false)
        XCTAssertFalse(engine.voiceProcessing)
        XCTAssertEqual(engine.installed, 2)
        tap.stop()
    }

    func testTheMicrophoneTapNeverInstallsTwoTapsAtOnce() async throws {
        let engine = FakeAudioEngine()
        let setup = RecordingSetup(label: "probe", mode: .measurement, options: [])
        let tap = MicrophoneTap(setups: [setup], engine: engine)
        tap.prepareSession = { _ in }
        try await tap.start { _ in }
        async let reconnecting: Void = tap.reconnect()
        async let switching: Void = tap.setVoiceProcessing(true)
        _ = try? await (reconnecting, switching)
        XCTAssertEqual(engine.duplicates, 0, "installTap darf nie auf einem belegten Bus laufen")
        tap.stop()
    }

    func testTheMicrophoneTapRunsWithAFakeEngine() async throws {
        let engine = FakeAudioEngine()
        let setup = RecordingSetup(label: "probe", mode: .measurement, options: [])
        let tap = MicrophoneTap(setups: [setup], engine: engine)
        tap.prepareSession = { _ in }
        let delivered = LockedValue(0)
        try await tap.start { _ in delivered.mutate { $0 += 1 } }
        XCTAssertTrue(tap.isRunning)
        XCTAssertTrue(tap.isFlowing)
        if let block = engine.tap,
           let buffer = AVAudioPCMBuffer(pcmFormat: engine.format, frameCapacity: 64) {
            buffer.frameLength = 64
            block(buffer, AVAudioTime(sampleTime: 0, atRate: 44_100))
        }
        try await tap.resume()
        try await tap.reconnect()
        tap.stop()
        XCTAssertFalse(tap.isRunning)
        XCTAssertGreaterThanOrEqual(engine.removed, 1)

        let failing = FakeAudioEngine()
        failing.failure = APIError(message: "kaputt")
        let second = MicrophoneTap(setups: [setup], engine: failing)
        second.prepareSession = { _ in }
        do {
            try await second.start { _ in }
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        XCTAssertEqual(failing.installed, 1)
        XCTAssertNil(failing.tap, "ein fehlgeschlagener Start darf keinen Tap hinterlassen")
        XCTAssertGreaterThanOrEqual(failing.removed, 1)
        second.stop()
    }

    func testSmokeTheRealEngineGuard() async {
        let real = MicrophoneTap()
        real.prepareSession = { _ in }
        try? await real.start { _ in }
        real.stop()
    }

    func testTheLastRecordingRoundHandsTheSessionBack() async throws {
        try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .measurement)
        await AudioRoute.shared.endRecording(atRound: AudioRound.recording.current)
        XCTAssertEqual(AVAudioSession.sharedInstance().category, .soloAmbient)
    }
}

@MainActor
extension VoiceLogicGapTests {
    func testTheSpeechRecognizerBranches() async {
        SystemSpeechRecognizer.authorizationStatusOverride = .authorized
        try? await SystemSpeechRecognizer.authorize()
        SystemSpeechRecognizer.authorizationStatusOverride = .denied
        do {
            try await SystemSpeechRecognizer.authorize()
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        SystemSpeechRecognizer.authorizationStatusOverride = .notDetermined
        SystemSpeechRecognizer.requestAuthorization = { true }
        try? await SystemSpeechRecognizer.authorize()
        SystemSpeechRecognizer.requestAuthorization = { false }
        do {
            try await SystemSpeechRecognizer.authorize()
            XCTFail("erwartet Fehler")
        } catch {}
        SystemSpeechRecognizer.authorizationStatusOverride = nil
        SystemSpeechRecognizer.requestAuthorization = { await SystemSpeechRecognizer.requestAuthorizationLive() }

        let recognizer = SystemSpeechRecognizer(locale: Locale(identifier: "de_DE"), timeout: 1)
        recognizer.isAvailableOverride = false
        do {
            _ = try await recognizer.transcribeAuthorized(wavURL: URL(fileURLWithPath: "/tmp/x.wav"))
            XCTFail("erwartet Fehler")
        } catch {}
        recognizer.isAvailableOverride = true
        recognizer.makeRequest = { url in SFSpeechURLRecognitionRequest(url: url) }
        _ = recognizer.makeRequest(URL(fileURLWithPath: "/tmp/x.wav"))
        recognizer.startTask = { _, _, handler in
            handler(nil, false, nil)
            handler("Hallo Welt", true, nil)
            return TestSpeechTask()
        }
        let text = try? await recognizer.transcribeAuthorized(wavURL: URL(fileURLWithPath: "/tmp/x.wav"))
        XCTAssertEqual(text, "Hallo Welt")
        recognizer.startTask = { _, _, handler in
            handler(nil, true, NSError(domain: "test", code: 1,
                                       userInfo: [NSLocalizedDescriptionKey: "No speech detected"]))
            return TestSpeechTask()
        }
        _ = try? await recognizer.transcribeAuthorized(wavURL: URL(fileURLWithPath: "/tmp/x.wav"))
        recognizer.startTask = { _, _, handler in
            handler(nil, true, APIError(message: "kaputt"))
            return TestSpeechTask()
        }
        _ = try? await recognizer.transcribeAuthorized(wavURL: URL(fileURLWithPath: "/tmp/x.wav"))
        recognizer.startTask = { _, _, _ in TestSpeechTask() }
        do {
            _ = try await recognizer.transcribeAuthorized(wavURL: URL(fileURLWithPath: "/tmp/x.wav"))
            XCTFail("erwartet Zeitablauf")
        } catch {}

        let answer = LockedValue<(@Sendable (Result<String, Error>) -> Void)?>(nil)
        let seen = LockedValue<[String]>([])
        answer.set { result in
            if case .success(let value) = result { seen.mutate { $0.append(value) } }
        }
        SystemSpeechRecognizer.receive(text: "Teil", isFinal: false, error: nil, answer: answer) { _ in false }
        SystemSpeechRecognizer.receive(text: "Ganz", isFinal: true, error: nil, answer: answer) { _ in false }
        SystemSpeechRecognizer.receive(text: nil, isFinal: true,
                                       error: NSError(domain: "x", code: 1,
                                                      userInfo: [NSLocalizedDescriptionKey: "No speech"]),
                                       answer: answer) { SystemSpeechRecognizer.reportsNoSpeech($0) }
        XCTAssertEqual(seen.current, ["Ganz", ""])
        XCTAssertTrue(SystemSpeechRecognizer.reportsNoSpeech(
            NSError(domain: "x", code: 1, userInfo: [NSLocalizedDescriptionKey: "No Speech Detected"])))
    }
}

@MainActor
extension VoiceLogicGapTests {
    func testSmokeTheHeadsetHandoverInternals() {
        let handover = HeadsetHandover()
        handover.yieldToPhone()
        handover.reclaim(preferring: [])
        handover.reclaim(preferring: ["unbekannt"])
        let note = Notification(name: AVAudioSession.routeChangeNotification, object: nil, userInfo: nil)
        let change = BluetoothPorts.change(from: note)
        handover.follow(change)
        _ = BluetoothPorts.ids(in: nil)
        _ = BluetoothPorts.availableInputs()
        handover.start()
        handover.stop()
    }
}

@MainActor
extension VoiceLogicGapTests {
    func testSmokeTheChimeFailurePath() {
        ChimePlayer.playFailure = APIError(message: "kaputt")
        ChimePlayer(tone: .sent).play()
        ChimePlayer.playFailure = nil
    }
}
