@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import GwenMobileKit
import XCTest

@MainActor
private final class GateSource: FinalizingTranscribing {
    let label = "gate"
    private(set) var isCapturing = false
    private(set) var stopCount = 0
    var settleText: String?
    private var onText: (@MainActor (String) -> Void)?

    func start(locale: Locale, hints: [String],
               onText: @escaping @MainActor (String) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {
        self.onText = onText
        isCapturing = true
    }

    func stop() {
        stopCount += 1
        isCapturing = false
    }

    func settle() async -> String? { settleText }

    func emit(_ text: String) { onText?(text) }
}

private struct EmptySpeakerStore: SpeakerProfileStoring {
    func load() -> SpeakerProfile? { nil }
    @discardableResult func save(_ profile: SpeakerProfile) -> Bool { false }
    @discardableResult func delete() -> Bool { true }
}

@MainActor
private final class FakeSpeakerGate: SpeakerGating {
    var isActive = true
    var verdict: SpeakerVerdict = .unknown
    var onVerdict: ((SpeakerVerdict) -> Void)?
    var final: SpeakerVerdict = .allowed
    private(set) var begins = 0
    private(set) var ends = 0

    func beginSession() { begins += 1 }
    func endSession() { ends += 1 }
    func finalVerdict() async -> SpeakerVerdict { final }

    func emit(_ value: SpeakerVerdict) {
        verdict = value
        onVerdict?(value)
    }
}

@MainActor
final class VoiceSpeakerGateTests: GwenTestCase {
    private func wait(_ milliseconds: Int = 120) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }

    private func makeVoice(_ source: GateSource, _ gate: FakeSpeakerGate) -> VoiceTranscriber {
        VoiceTranscriber(makeSource: { source }, microphoneAllowed: { true }, speakerGate: gate)
    }

    func testSpeechWaitsForTheSpeakerAndThenDelivers() async {
        let source = GateSource()
        let gate = FakeSpeakerGate()
        let voice = makeVoice(source, gate)
        voice.timing = .conversation(silence: 0.4)
        var delivered = ""
        var speech = 0
        var rejected = 0
        voice.converse(onText: { delivered = $0 }, onSpeech: { speech += 1 }, onCancel: {},
                       onRejected: { rejected += 1 })
        await wait(150)
        source.emit("Hallo Welt")
        await wait(120)
        XCTAssertEqual(speech, 0)
        XCTAssertTrue(delivered.isEmpty)
        gate.emit(.allowed)
        await wait(120)
        XCTAssertEqual(speech, 1)
        await wait(600)
        XCTAssertEqual(delivered, "Hallo Welt")
        XCTAssertEqual(rejected, 0)
        XCTAssertGreaterThanOrEqual(gate.begins, 1)
        XCTAssertGreaterThanOrEqual(gate.ends, 1)
        XCTAssertEqual(voice.state, .idle)
    }

    func testRejectedSpeakerNeitherInterruptsNorDelivers() async {
        let source = GateSource()
        let gate = FakeSpeakerGate()
        gate.final = .rejected
        let voice = makeVoice(source, gate)
        voice.timing = .conversation(silence: 0.4)
        var delivered = ""
        var speech = 0
        var rejected = 0
        voice.converse(onText: { delivered = $0 }, onSpeech: { speech += 1 }, onCancel: {},
                       onRejected: { rejected += 1 })
        await wait(150)
        source.emit("Hallo Welt")
        await wait(120)
        gate.emit(.rejected)
        await wait(700)
        XCTAssertEqual(speech, 0)
        XCTAssertTrue(delivered.isEmpty)
        XCTAssertEqual(rejected, 1)
        XCTAssertEqual(voice.state, .idle)
        XCTAssertEqual(source.stopCount, 1)
    }

    func testCancelWordWaitsForTheSpeaker() async {
        let source = GateSource()
        let gate = FakeSpeakerGate()
        let voice = makeVoice(source, gate)
        voice.signals = VoiceSignals(wake: "", stop: "stopp", cancel: "abbrechen")
        voice.timing = .conversation(silence: 0.08)
        var delivered = ""
        var cancels = 0
        voice.converse(onText: { delivered = $0 }, onSpeech: {}, onCancel: { cancels += 1 })
        await wait(150)
        source.emit("Hallo abbrechen")
        await wait(120)
        XCTAssertEqual(cancels, 0)
        gate.emit(.allowed)
        await wait(120)
        XCTAssertEqual(cancels, 1)
        XCTAssertTrue(delivered.isEmpty)
        voice.cancel()
    }

    func testRejectedCancelWordDoesNotStop() async {
        let source = GateSource()
        let gate = FakeSpeakerGate()
        gate.final = .rejected
        let voice = makeVoice(source, gate)
        voice.signals = VoiceSignals(wake: "", stop: "stopp", cancel: "abbrechen")
        voice.timing = .conversation(silence: 0.08)
        var cancels = 0
        var rejected = 0
        voice.converse(onText: { _ in }, onSpeech: {}, onCancel: { cancels += 1 },
                       onRejected: { rejected += 1 })
        await wait(150)
        source.emit("Hallo abbrechen")
        await wait(700)
        XCTAssertEqual(cancels, 0)
        XCTAssertEqual(rejected, 1)
        XCTAssertEqual(voice.state, .idle)
    }

    func testAMissingProfileFailsClosed() async {
        let gate = SpeakerGate(store: EmptySpeakerStore(), isEnabled: { true }, sensitivity: { .normal })
        gate.beginSession()
        XCTAssertTrue(gate.isActive)
        let verdict = await gate.finalVerdict()
        XCTAssertEqual(verdict, .rejected)
    }

    func testAnInactiveGateKeepsTheOldConversationBehaviour() async {
        let source = GateSource()
        let gate = FakeSpeakerGate()
        gate.isActive = false
        let voice = makeVoice(source, gate)
        voice.timing = .conversation(silence: 0.08)
        var delivered = ""
        var speech = 0
        voice.converse(onText: { delivered = $0 }, onSpeech: { speech += 1 }, onCancel: {})
        await wait(150)
        source.emit("Hallo Welt")
        await wait(120)
        XCTAssertEqual(speech, 1)
        await wait(600)
        XCTAssertEqual(delivered, "Hallo Welt")
    }
}
