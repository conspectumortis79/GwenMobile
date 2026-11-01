@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import AVFoundation
import XCTest
import GwenMobileKit

@MainActor
private final class FakeTranscribing: FinalizingTranscribing {
    let label = "fake"
    var isCapturing = false
    var startError: Error?
    var settleText: String?
    private(set) var stopCount = 0
    private(set) var starts = 0
    private var onText: (@MainActor (String) -> Void)?
    private var onFailure: (@MainActor (String) -> Void)?

    func start(locale: Locale, hints: [String],
               onText: @escaping @MainActor (String) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {
        starts += 1
        if let startError { throw startError }
        self.onText = onText
        self.onFailure = onFailure
        isCapturing = true
    }

    func stop() {
        stopCount += 1
        isCapturing = false
    }

    func settle() async -> String? { settleText }

    func emit(_ text: String) { onText?(text) }
    func fail(_ message: String) { onFailure?(message) }
}

@MainActor
private final class SilentCue: SoundCueing {
    private(set) var plays = 0
    func play() { plays += 1 }
}

@MainActor
final class VoiceTranscriberCoverageTests: GwenTestCase {
    private func makeVoice(_ source: FakeTranscribing,
                           cue: SilentCue = SilentCue()) -> VoiceTranscriber {
        VoiceTranscriber(makeSource: { source }, microphoneAllowed: { true }, sentCue: cue)
    }

    func testRecordingStartsAndDeliversTheSpokenText() async throws {
        let source = FakeTranscribing()
        let voice = makeVoice(source)
        var delivered = ""
        voice.start { delivered = $0 }
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(voice.state, .recording)
        XCTAssertTrue(voice.probeRecorderActive)
        XCTAssertEqual(voice.sourceLabel, "fake")
        source.emit("Hallo Welt")
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(voice.heardSoFar, "Hallo Welt")
        voice.stopAndTranscribe()
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(delivered, "Hallo Welt")
        XCTAssertEqual(voice.state, .idle)
        XCTAssertEqual(source.stopCount, 1)
    }

    func testSettledTextWinsOverTheLiveText() async throws {
        let source = FakeTranscribing()
        source.settleText = "Endgültiger Satz"
        let voice = makeVoice(source)
        var delivered = ""
        voice.start { delivered = $0 }
        try await Task.sleep(for: .milliseconds(120))
        source.emit("vorläufig")
        try await Task.sleep(for: .milliseconds(60))
        voice.stopAndTranscribe { text in delivered = "replacement:" + text }
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(delivered, "replacement:Endgültiger Satz")
    }

    func testListeningWithoutWakeStaysWaiting() async throws {
        let source = FakeTranscribing()
        let voice = makeVoice(source)
        voice.signals = VoiceSignals(wake: "computer", stop: "stopp", cancel: "abbrechen")
        var delivered = ""
        voice.listen { delivered = $0 }
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(voice.state, .waiting)
        XCTAssertTrue(voice.lastSessionListened)
        XCTAssertFalse(voice.wakeWordTriggered)
        source.emit("einfach so geredet")
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(delivered.isEmpty)
        XCTAssertFalse(voice.wakeWordTriggered)
        source.emit("computer mach das Licht an")
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(voice.heardSoFar.contains("Licht"))
        XCTAssertTrue(voice.wakeWordTriggered)
        voice.cancel()
        XCTAssertEqual(voice.state, .idle)
        XCTAssertFalse(voice.wakeWordTriggered)
    }

    func testTheCancelListenerIgnoresSpeechAndStopsOnTheWord() async throws {
        let source = FakeTranscribing()
        let voice = makeVoice(source)
        voice.signals = VoiceSignals(wake: "computer", stop: "stopp", cancel: "abbrechen")
        voice.timing = VoiceTiming(silence: 0.05, nothingSaid: 0.05, maximum: 0.1)
        var cancels = 0
        voice.listenForCancel { cancels += 1 }
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertTrue(voice.isCancelSession)
        XCTAssertEqual(voice.state, .recording)
        source.emit("Hallo Welt")
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(voice.state, .recording, "das Abbruch-Zuhoeren endet nicht durch Stille")
        XCTAssertEqual(voice.liveText, "")
        XCTAssertEqual(cancels, 0)
        source.emit("Hallo abbrechen")
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(cancels, 1)
        XCTAssertEqual(voice.state, .idle)
        XCTAssertFalse(voice.isCancelSession)
    }

    func testStoppingTheCancelListenerDeliversNothing() async throws {
        let source = FakeTranscribing()
        let voice = makeVoice(source)
        var cancels = 0
        voice.listenForCancel { cancels += 1 }
        try await Task.sleep(for: .milliseconds(120))
        voice.stopAndTranscribe()
        XCTAssertEqual(voice.state, .idle)
        XCTAssertEqual(cancels, 0)
    }

    func testRestartingTheCancelListenerKeepsItCancellable() async throws {
        let source = FakeTranscribing()
        var builds = 0
        let voice = VoiceTranscriber(makeSource: { builds += 1; return source },
                                     sentCue: SilentCue())
        voice.signals = VoiceSignals(wake: "computer", stop: "stopp", cancel: "abbrechen")
        var cancels = 0
        voice.listenForCancel { cancels += 1 }
        try await Task.sleep(for: .milliseconds(120))
        voice.restartListening()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(builds, 2)
        XCTAssertTrue(voice.isCancelSession)
        source.emit("abbrechen")
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(cancels, 1)
        XCTAssertEqual(voice.state, .idle)
    }

    func testTheWakeWordMarksTheRecordingAndClearsAfterDelivery() async throws {
        let source = FakeTranscribing()
        let voice = makeVoice(source)
        voice.signals = VoiceSignals(wake: "computer", stop: "stopp", cancel: "abbrechen")
        var delivered = ""
        voice.listen { delivered = $0 }
        try await Task.sleep(for: .milliseconds(120))
        source.emit("computer mach das Licht an")
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(voice.wakeWordTriggered)
        voice.stopAndTranscribe()
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(delivered, "mach das Licht an")
        XCTAssertFalse(voice.wakeWordTriggered)
    }

    func testTheSpokenWakeGreetingIsRemovedFromTheRequest() async throws {
        let source = FakeTranscribing()
        let voice = makeVoice(source)
        voice.signals = VoiceSignals(wake: "computer", stop: "stopp", cancel: "abbrechen")
        voice.onWakeWord = { "Ich höre" }
        var delivered = ""
        voice.listen { delivered = $0 }
        try await Task.sleep(for: .milliseconds(120))
        source.emit("computer Ich höre mach das Licht an")
        try await Task.sleep(for: .milliseconds(80))
        voice.stopAndTranscribe()
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(delivered, "mach das Licht an")
    }

    func testADirectDeliveryKeepsTheWakeWordFlagOff() async throws {
        let source = FakeTranscribing()
        let voice = makeVoice(source)
        var delivered = ""
        voice.start { delivered = $0 }
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertFalse(voice.wakeWordTriggered)
        source.emit("Hallo Welt")
        voice.stopAndTranscribe()
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(delivered, "Hallo Welt")
        XCTAssertFalse(voice.wakeWordTriggered)
    }

    func testConversationSpeechNeedsAPhraseOrALongerWord() {
        XCTAssertFalse(VoiceTranscriber.confirmsConversationSpeech(""))
        XCTAssertFalse(VoiceTranscriber.confirmsConversationSpeech("Hi"))
        XCTAssertFalse(VoiceTranscriber.confirmsConversationSpeech("Ich"))
        XCTAssertFalse(VoiceTranscriber.confirmsConversationSpeech("Bist"))
        XCTAssertTrue(VoiceTranscriber.confirmsConversationSpeech("Moment"))
        XCTAssertTrue(VoiceTranscriber.confirmsConversationSpeech("Warte"))
        XCTAssertTrue(VoiceTranscriber.confirmsConversationSpeech("Hallo du"))
    }

    func testConversationDiscardsASingleShortWordAndKeepsListening() async throws {
        let source = FakeTranscribing()
        let voice = makeVoice(source)
        voice.timing = .conversation(silence: 0.08)
        var delivered = ""
        var speech = 0
        voice.converse(onText: { delivered = $0 }, onSpeech: { speech += 1 }, onCancel: {})
        try await Task.sleep(for: .milliseconds(120))
        source.emit("Ich")
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(delivered.isEmpty)
        XCTAssertEqual(speech, 0)
        XCTAssertEqual(voice.state, .recording)
        source.emit("Moment ich habe eine Frage")
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(speech, 1)
        XCTAssertEqual(delivered, "Moment ich habe eine Frage")
    }

    func testConversationCancelWordStopsWithoutDelivery() async throws {
        let source = FakeTranscribing()
        let voice = makeVoice(source)
        voice.signals = VoiceSignals(wake: "computer", stop: "stopp jetzt", cancel: "abbrechen")
        voice.timing = .conversation(silence: 0.08)
        var delivered = ""
        var speech = 0
        var cancels = 0
        voice.converse(onText: { delivered = $0 }, onSpeech: { speech += 1 }, onCancel: { cancels += 1 })
        try await Task.sleep(for: .milliseconds(120))
        source.emit("Hallo")
        try await Task.sleep(for: .milliseconds(80))
        source.emit("Hallo abbrechen")
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(cancels, 1)
        XCTAssertEqual(speech, 1)
        XCTAssertTrue(delivered.isEmpty)
        voice.cancel()
    }

    func testConversationCancelWordMayBeOneShortWord() async throws {
        let source = FakeTranscribing()
        let voice = makeVoice(source)
        voice.signals = VoiceSignals(wake: "computer", stop: "stopp", cancel: "stop")
        voice.timing = .conversation(silence: 0.08)
        var delivered = ""
        var speech = 0
        var cancels = 0
        voice.converse(onText: { delivered = $0 }, onSpeech: { speech += 1 }, onCancel: { cancels += 1 })
        try await Task.sleep(for: .milliseconds(120))
        source.emit("stop")
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(cancels, 1)
        XCTAssertEqual(speech, 0)
        XCTAssertTrue(delivered.isEmpty)
        voice.cancel()
    }

    func testConversationModeSignalsSpeechOnceAndDeliversWithoutWake() async throws {
        let source = FakeTranscribing()
        let voice = makeVoice(source)
        voice.signals = VoiceSignals(wake: "computer", stop: "jetzt senden", cancel: "abbrechen")
        voice.timing = .conversation(silence: 0.08)
        var delivered = ""
        var speech = 0
        voice.converse(onText: { delivered = $0 }, onSpeech: { speech += 1 }, onCancel: {})
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(voice.state, .recording)
        source.emit("Hallo")
        try await Task.sleep(for: .milliseconds(80))
        source.emit("Hallo Welt")
        XCTAssertEqual(speech, 1)
        XCTAssertTrue(delivered.isEmpty)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(delivered, "Hallo Welt")
        XCTAssertEqual(voice.state, .idle)
    }

    func testConversationModeTreatsTheStopWordAsSpeech() async throws {
        let source = FakeTranscribing()
        let voice = makeVoice(source)
        voice.signals = VoiceSignals(wake: "computer", stop: "jetzt senden", cancel: "abbrechen")
        voice.timing = .conversation(silence: 0.08)
        var delivered = ""
        var cancels = 0
        voice.converse(onText: { delivered = $0 }, onSpeech: {}, onCancel: { cancels += 1 })
        try await Task.sleep(for: .milliseconds(120))
        source.emit("jetzt senden")
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(delivered, "jetzt senden")
        XCTAssertEqual(cancels, 0)
        XCTAssertEqual(voice.state, .idle)
    }

    func testConversationModeKeepsWaitingWhenNothingWasSaid() async throws {
        let source = FakeTranscribing()
        let voice = makeVoice(source)
        voice.timing = VoiceTiming(silence: 0.08, nothingSaid: 0.1, maximum: 0.2)
        voice.converse(onText: { _ in }, onSpeech: {}, onCancel: {})
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(voice.state, .recording)
        XCTAssertNil(voice.lastError)
        voice.cancel()
        XCTAssertEqual(voice.state, .idle)
    }

    func testRestartingAConversationKeepsItsCallbacks() async throws {
        let source = FakeTranscribing()
        var builds = 0
        let voice = VoiceTranscriber(makeSource: { builds += 1; return source },
                                     sentCue: SilentCue())
        voice.timing = .conversation(silence: 0.08)
        var delivered = ""
        voice.converse(onText: { delivered = $0 }, onSpeech: {}, onCancel: {})
        try await Task.sleep(for: .milliseconds(120))
        voice.restartConversation()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(builds, 2)
        XCTAssertEqual(voice.state, .recording)
        source.emit("weiter")
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(delivered, "weiter")
    }

    func testAFailingSourceShowsTheError() async throws {
        let source = FakeTranscribing()
        source.startError = APIError(message: "mikrofon weg")
        let voice = makeVoice(source)
        voice.start { _ in }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(voice.state, .idle)
        XCTAssertEqual(voice.lastError?.message, "mikrofon weg")
    }

    func testAFailureDuringRecordingEndsTheSession() async throws {
        let source = FakeTranscribing()
        let voice = makeVoice(source)
        voice.start { _ in }
        try await Task.sleep(for: .milliseconds(120))
        source.fail("Verbindung verloren")
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(voice.state, .idle)
        XCTAssertNotNil(voice.lastError)
    }

    func testRestartListeningBuildsANewSession() async throws {
        let source = FakeTranscribing()
        var builds = 0
        let voice = VoiceTranscriber(makeSource: { builds += 1; return source },
                                     sentCue: SilentCue())
        voice.listen { _ in }
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(builds, 1)
        voice.restartListening()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(builds, 2)
        XCTAssertEqual(voice.state, .waiting)
        voice.cancel()
    }

    func testTheTickerEndsSilenceAndDelivers() async throws {
        let source = FakeTranscribing()
        let voice = makeVoice(source)
        voice.timing = VoiceTiming(silence: 0.08, nothingSaid: 0.15, maximum: 30)
        var delivered = ""
        voice.start { delivered = $0 }
        try await Task.sleep(for: .milliseconds(120))
        source.emit("Kurzer Satz")
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(delivered, "Kurzer Satz")
        XCTAssertEqual(voice.state, .idle)
    }

    func testTheTickerGivesUpWhenNothingWasSaid() async throws {
        let source = FakeTranscribing()
        let voice = makeVoice(source)
        voice.timing = VoiceTiming(silence: 0.08, nothingSaid: 0.1, maximum: 30)
        voice.start { _ in }
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(voice.state, .idle)
        XCTAssertNotNil(voice.lastError)
    }

    func testCancellingWhileWaitingStopsTheSource() async throws {
        let source = FakeTranscribing()
        let voice = makeVoice(source)
        voice.listen { _ in }
        try await Task.sleep(for: .milliseconds(120))
        voice.cancel()
        XCTAssertEqual(voice.state, .idle)
        XCTAssertGreaterThanOrEqual(source.stopCount, 1)
        voice.cancel()
        voice.stopAndTranscribe()
    }
}
