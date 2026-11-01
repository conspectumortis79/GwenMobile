@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import AVFoundation
import XCTest
import GwenMobileKit

@MainActor
private final class VoiceEngineFakeSource: FinalizingTranscribing {
    let label = "fake"
    var isCapturing = false
    var failure: Error?
    private(set) var stopCount = 0

    func start(locale: Locale, hints: [String],
               onText: @escaping @MainActor (String) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {
        if let failure { throw failure }
        isCapturing = true
    }

    func stop() {
        stopCount += 1
        isCapturing = false
    }

    func settle() async -> String? { "settled" }
}

@MainActor
final class VoiceEngineCoverageTests: GwenTestCase {
    private func pcm(_ amplitude: Float, sampleRate: Double = 44_100, channels: AVAudioChannelCount = 1,
                     frames: AVAudioFrameCount = 512) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        if let data = buffer.floatChannelData {
            for channel in 0..<Int(channels) {
                for frame in 0..<Int(frames) {
                    data[channel][frame] = amplitude * sinf(Float(frame) * 0.1)
                }
            }
        }
        return buffer
    }

    func testTheLevelMeterReportsThrottledPeaks() {
        let seen = LockedValue<[Int]>([])
        let meter = AudioLevelMeter { value in seen.mutate { $0.append(value) } }
        meter.measure(peak: 0.5, at: Date())
        meter.measure(peak: 0.2, at: Date().addingTimeInterval(5))
        meter.measure(pcm(0.3), at: Date().addingTimeInterval(10))
        XCTAssertFalse(seen.current.isEmpty)
        XCTAssertNotEqual(AudioLevelMeter.decibels(0), AudioLevelMeter.decibels(0.5))
    }

    func testTheSpeechLevelBoostAmplifiesQuietInput() {
        let buffer = pcm(0.05)
        let before = SpeechLevelBoost.peak(of: buffer)
        SpeechLevelBoost.standard.amplify(buffer)
        XCTAssertGreaterThan(SpeechLevelBoost.peak(of: buffer), before)
        XCTAssertTrue(SpeechLevelBoost.standard.isActive)
        XCTAssertFalse(SpeechLevelBoost.off.isActive)
        SpeechLevelBoost.off.amplify(buffer)
        let silent = pcm(0)
        SpeechLevelBoost.standard.amplify(silent)
        XCTAssertEqual(SpeechLevelBoost.peak(of: silent), 0)
        SpeechLevelBoost(maximumGain: 0).amplify(buffer, peak: 1)
    }

    func testThePreferredSourcePicksTheFirstWorkingCandidate() async throws {
        let failing = VoiceEngineFakeSource()
        failing.failure = APIError(message: "kaputt")
        let good = VoiceEngineFakeSource()
        let preferred = PreferredSpeechSource(candidates: [{ failing }, { good }])
        try await preferred.start(locale: Locale(identifier: "de_DE"), hints: [],
                                  onText: { _ in }, onFailure: { _ in })
        XCTAssertTrue(preferred.isCapturing)
        XCTAssertEqual(preferred.label, "fake")
        let settled = await preferred.settle()
        XCTAssertEqual(settled, "settled")
        preferred.stop()
        XCTAssertEqual(good.stopCount, 1)
        let dead = PreferredSpeechSource(candidates: [{ failing }])
        do {
            try await dead.start(locale: Locale(identifier: "de_DE"), hints: [],
                                 onText: { _ in }, onFailure: { _ in })
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        XCTAssertFalse(dead.isCapturing)
        XCTAssertEqual(dead.label, "keine")
        dead.stop()
    }

    func testTheAnalyzerFeedConvertsBuffers() {
        let target = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let feed = AnalyzerFeed(target: target)
        let input = pcm(0.1, sampleRate: 22_050, channels: 1)
        let converted = feed.converted(input)
        XCTAssertNotNil(converted)
        XCTAssertEqual(converted?.format.sampleRate, 44_100)
        let empty = AVAudioPCMBuffer(pcmFormat: input.format, frameCapacity: 512)!
        XCTAssertNil(feed.converted(empty))
        XCTAssertTrue(feed.traceLine.contains("puffer="))
    }

    func testTheSpeechSourcesBehaveWithoutStart() async {
        let analyzer = AnalyzerSpeechSource(feed: TestAudioFeed())
        XCTAssertEqual(analyzer.label, "speechanalyzer")
        XCTAssertFalse(analyzer.isCapturing)
        analyzer.stop()
        let settled = await analyzer.settle()
        XCTAssertNil(settled)
        let buffered = BufferSpeechSource(feed: TestAudioFeed())
        XCTAssertFalse(buffered.isCapturing)
        XCTAssertFalse(buffered.label.isEmpty)
        buffered.stop()
    }

    func testTheRecognizerHelpers() {
        XCTAssertFalse(SystemSpeechRecognizer.reportsNoSpeech(APIError(message: "irgendwas")))
        let noSpeech = NSError(domain: "test", code: 1,
                               userInfo: [NSLocalizedDescriptionKey: "No speech detected"])
        XCTAssertTrue(SystemSpeechRecognizer.reportsNoSpeech(noSpeech))
        _ = SystemSpeechRecognizer(locale: Locale(identifier: "de_DE"))
    }

    func testSmokeTheMicrophoneTapStopsSafely() {
        let tap = MicrophoneTap()
        tap.stop()
    }

    func testTheCuePreviewAndSoundGroups() {
        _ = CuePreview(tone: .sent)
        let sounds = [SystemSound(path: "/a/Tink.caf", name: "Tink", folder: "A"),
                      SystemSound(path: "/b/Ping.caf", name: "Ping", folder: "B"),
                      SystemSound(path: "/b/Pong.caf", name: "Pong", folder: "B")]
        let grouped = SystemSoundGroup.grouped(sounds, matching: "")
        XCTAssertEqual(grouped.map(\.folder), ["A", "B"])
        XCTAssertEqual(grouped.last?.sounds.count, 2)
        let filtered = SystemSoundGroup.grouped(sounds, matching: "po")
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.sounds.map(\.name), ["Pong"])
    }
}
