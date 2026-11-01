@testable import GwenMobileFeatureCore
import AVFoundation
import XCTest
import GwenMobileKit

private final class InstantSpeech: AVSpeechSynthesizer {
    override var isSpeaking: Bool { false }

    override func speak(_ utterance: AVSpeechUtterance) {
        delegate?.speechSynthesizer?(self, didFinish: utterance)
    }
}

@MainActor
final class SpeechStreamTests: GwenTestCase {
    func testAFinishedUtteranceEndsThePlaybackRound() async throws {
        let engine = SpeechSynthesizer.makeEngine
        SpeechSynthesizer.makeEngine = { InstantSpeech() }
        defer { SpeechSynthesizer.makeEngine = engine }
        let speech = SpeechSynthesizer()
        let before = AudioRound.playback.current
        speech.speak(text: "Hallo Welt")
        XCTAssertTrue(speech.isSpeaking)
        for _ in 0..<200 where speech.isSpeaking {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(speech.isSpeaking)
        XCTAssertEqual(AudioRound.playback.current, before + 1)
    }

    func testTheStreamSuppressesEverythingAfterTheSearchMarker() {
        let speech = SpeechSynthesizer()
        speech.beginStream(voiceIdentifier: VoiceOption.systemDefaultID)
        speech.stream("Das ist ein ausreichend langer Satz der Antwort mit [[SEARCH]].")
        XCTAssertFalse(speech.takeStreamed())
        speech.endStream()
        speech.stop()
    }

    func testTheStreamEnqueuesSentencesAndThenQueuesFurtherOnes() async {
        let speech = SpeechSynthesizer()
        speech.beginStream(voiceIdentifier: VoiceOption.systemDefaultID)
        speech.stream("Das ist ein ausreichend langer erster Satz der Antwort. ")
        XCTAssertTrue(speech.takeStreamed())
        try? await Task.sleep(for: .milliseconds(100))
        speech.stream("Das ist ein ausreichend langer zweiter Satz der Antwort. ")
        XCTAssertTrue(speech.takeStreamed())
        speech.endStream()
        speech.stop()
    }
}
