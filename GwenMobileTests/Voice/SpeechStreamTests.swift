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

private final class HoldingSpeech: AVSpeechSynthesizer {
    override func speak(_ utterance: AVSpeechUtterance) {}

    override func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool { true }
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

    func testTheSilentWaitWakesUpWhenTheSpeechStops() async throws {
        let engine = SpeechSynthesizer.makeEngine
        SpeechSynthesizer.makeEngine = { HoldingSpeech() }
        defer { SpeechSynthesizer.makeEngine = engine }
        let speech = SpeechSynthesizer()
        speech.speak(text: "Hallo Welt")
        let finished = LockedValue(false)
        let waiting = Task { @MainActor in
            await speech.waitUntilSilent(timeout: .seconds(30))
            finished.set(true)
        }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(finished.current)
        speech.stop()
        await waiting.value
        XCTAssertTrue(finished.current)
    }

    func testTheSilentWaitGivesUpAfterItsTimeout() async throws {
        let engine = SpeechSynthesizer.makeEngine
        SpeechSynthesizer.makeEngine = { HoldingSpeech() }
        defer { SpeechSynthesizer.makeEngine = engine }
        let speech = SpeechSynthesizer()
        speech.speak(text: "Hallo Welt")
        XCTAssertTrue(speech.isSpeaking)
        await speech.waitUntilSilent(timeout: .milliseconds(30))
        XCTAssertTrue(speech.isSpeaking)
        speech.stop()
        XCTAssertFalse(speech.isSpeaking)
        await speech.waitUntilSilent(timeout: .milliseconds(30))
        XCTAssertFalse(speech.isSpeaking)
    }

    func testRapidRespeakDoesNotDropTheSecondUtteranceWhileRouteStarts() async throws {
        let engine = SpeechSynthesizer.makeEngine
        let delay = AudioRoute.playbackDelay
        let spoken = LockedValue<[String]>([])
        final class RecordingSpeech: AVSpeechSynthesizer {
            let spoken: LockedValue<[String]>
            init(spoken: LockedValue<[String]>) {
                self.spoken = spoken
                super.init()
            }
            override func speak(_ utterance: AVSpeechUtterance) {
                spoken.mutate { $0.append(utterance.speechString) }
                delegate?.speechSynthesizer?(self, didFinish: utterance)
            }
        }
        AudioRoute.playbackDelay = .milliseconds(40)
        SpeechSynthesizer.makeEngine = { RecordingSpeech(spoken: spoken) }
        defer {
            SpeechSynthesizer.makeEngine = engine
            AudioRoute.playbackDelay = delay
        }
        let speech = SpeechSynthesizer()
        speech.speak(text: "Erster Satz")
        speech.speak(text: "Zweiter Satz")
        for _ in 0..<200 where speech.isSpeaking {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(speech.isSpeaking)
        XCTAssertEqual(spoken.current, ["Zweiter Satz"])
    }
}
