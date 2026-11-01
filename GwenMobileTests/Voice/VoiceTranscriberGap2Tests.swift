@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import GwenMobileKit
import XCTest

@MainActor
private final class TestVoiceSource: FinalizingTranscribing {
    let label = "test"
    private(set) var isCapturing = false
    var settleText: String?
    var startText: String?
    var lateText: String?

    func start(locale: Locale, hints: [String],
               onText: @escaping @MainActor (String) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {
        isCapturing = true
        if let startText { onText(startText) }
        if let lateText {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(60))
                onText(lateText)
            }
        }
    }

    func stop() { isCapturing = false }
    func settle() async -> String? { settleText }
}

@MainActor
private final class HeldSettleSource: FinalizingTranscribing {
    let label = "gehalten"
    private(set) var isCapturing = false
    private var release: CheckedContinuation<Void, Never>?

    var isSettling: Bool { release != nil }

    func start(locale: Locale, hints: [String],
               onText: @escaping @MainActor (String) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {
        isCapturing = true
    }

    func stop() { isCapturing = false }

    func settle() async -> String? {
        await withCheckedContinuation { release = $0 }
        return "alter Satz"
    }

    func finish() {
        release?.resume()
        release = nil
    }
}

@MainActor
private final class SourceQueue {
    private var waiting: [any LiveTranscribing]
    private(set) var delivered: [String] = []

    init(_ sources: [any LiveTranscribing]) {
        waiting = sources
    }

    func next() -> any LiveTranscribing { waiting.isEmpty ? TestVoiceSource() : waiting.removeFirst() }

    func note(_ text: String) { delivered.append(text) }
}

@MainActor
final class VoiceTranscriberGap2Tests: GwenTestCase {
    func testALateSettleNeverReachesTheNextSession() async {
        let held = HeldSettleSource()
        let queue = SourceQueue([held, TestVoiceSource()])
        let voice = VoiceTranscriber(makeSource: { queue.next() }, microphoneAllowed: { true })
        voice.start { queue.note($0) }
        await wait(120)
        XCTAssertEqual(voice.state, .recording)
        voice.stopAndTranscribe()
        await wait(60)
        XCTAssertTrue(held.isSettling)
        voice.cancel()
        voice.start { queue.note("neu: " + $0) }
        await wait(120)
        XCTAssertEqual(voice.state, .recording)
        held.finish()
        await wait(120)
        XCTAssertEqual(voice.state, .recording)
        XCTAssertTrue(queue.delivered.isEmpty)
        voice.cancel()
    }

    private func wait(_ ms: Int = 120) async {
        try? await Task.sleep(for: .milliseconds(ms))
    }

    func testTheMicrophonePortDefaultsAndTheDefaultVoice() async {
        XCTAssertTrue(VoiceMicrophonePort.allowed())
        var called = false
        VoiceMicrophonePort.request { called = $0 }
        XCTAssertTrue(called)
        let voice = VoiceTranscriber()
        voice.start { _ in }
        await wait(120)
        voice.cancel()
        XCTAssertEqual(voice.sourceLabel, "-")
        XCTAssertFalse(voice.probeRecorderActive)
        XCTAssertEqual(voice.heardSoFar, "")
        XCTAssertFalse(voice.lastSessionListened)
    }

    private func makeGrantedVoice() -> VoiceTranscriber {
        let allowed = LockedValue(false)
        VoiceMicrophonePort.allowed = { allowed.current }
        VoiceMicrophonePort.request = { done in
            allowed.set(true)
            done(true)
        }
        return VoiceTranscriber(makeSource: { TestVoiceSource() },
                                microphoneAllowed: { allowed.current })
    }

    func testTheGrantedMicrophoneRequestStartsTheSession() async {
        let voice = makeGrantedVoice()
        voice.start { _ in }
        await wait(200)
        XCTAssertEqual(voice.state, .recording)
        voice.cancel()
    }

    func testTheGrantedMicrophoneStartsTheCancelListener() async {
        let voice = makeGrantedVoice()
        voice.listenForCancel {}
        await wait(200)
        XCTAssertTrue(voice.isCancelSession)
        XCTAssertEqual(voice.state, .recording)
        voice.cancel()
    }

    func testTheCancelVerdictEndsTheSession() async {
        let source = TestVoiceSource()
        source.lateText = "abbrechen"
        let voice = VoiceTranscriber(makeSource: { source }, microphoneAllowed: { true })
        voice.signals = VoiceSignals(wake: "", stop: "senden", cancel: "abbrechen")
        voice.start { _ in }
        await wait(250)
        XCTAssertEqual(voice.state, .idle)
    }

    func testTheDeniedMicrophoneIsReported() async {
        VoiceMicrophonePort.request = { done in done(false) }
        let voice = VoiceTranscriber(makeSource: { TestVoiceSource() }, microphoneAllowed: { false })
        voice.start { _ in }
        await wait(200)
        XCTAssertEqual(voice.lastError?.message, L.t("mic_denied"))
    }

    func testTheWaitingCancelAndEmptySettle() async {
        let empty = TestVoiceSource()
        empty.settleText = ""
        let voice = VoiceTranscriber(makeSource: { empty }, microphoneAllowed: { true })
        voice.start { _ in }
        await wait()
        voice.stopAndTranscribe()
        await wait(200)
        XCTAssertEqual(voice.lastError?.message, L.t("asr_empty"))

        let waitingSource = TestVoiceSource()
        let waiting = VoiceTranscriber(makeSource: { waitingSource }, microphoneAllowed: { true })
        waiting.listen { _ in }
        await wait()
        waiting.stopAndTranscribe()
        XCTAssertEqual(waiting.state, .idle)
    }

    func testTheWakeWordInASettledTranscriptIsTaken() async {
        let source = TestVoiceSource()
        source.settleText = "hey gwen spiele musik"
        source.lateText = "hey gwen"
        let voice = VoiceTranscriber(makeSource: { source }, microphoneAllowed: { true })
        voice.signals = VoiceSignals(wake: "hey gwen", stop: "senden", cancel: "abbrechen")
        let delivered = LockedValue<String?>(nil)
        voice.listen { delivered.set($0) }
        await wait(200)
        XCTAssertEqual(voice.state, .recording)
        voice.stopAndTranscribe()
        await wait(300)
        XCTAssertEqual(delivered.current, "spiele musik")
    }

    func testTheHardwareStubsAnswer() async throws {
        let tap = StubAudioTap()
        try await tap.start { _ in }
        XCTAssertTrue(tap.isRunning)
        tap.stop()
        XCTAssertFalse(tap.isRunning)
        try await tap.resume()
        try await tap.reconnect()
        StubDisruptions().start { _ in }
        StubDisruptions().stop()
        StubHeadsets().start()
        StubHeadsets().stop()
        _ = VoiceHardwarePort.makeTap()
        _ = VoiceHardwarePort.makeDisruptions()
        _ = VoiceHardwarePort.makeHeadsets()
        XCTAssertTrue(true)
    }
}
