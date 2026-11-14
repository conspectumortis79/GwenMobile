@testable import GwenMobileFeatureCore
import AVFoundation
import XCTest

final class SpeechLevelBoostTests: XCTestCase {
    private func buffer(_ samples: [Float], channels: Int = 1) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: AVAudioChannelCount(channels))!
        let frames = samples.count / channels
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        for channel in 0..<channels {
            for frame in 0..<frames {
                buffer.floatChannelData![channel][frame] = samples[frame * channels + channel]
            }
        }
        return buffer
    }

    private func samples(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let frames = Int(buffer.frameLength)
        return (0..<Int(buffer.format.channelCount)).flatMap { channel in
            (0..<frames).map { buffer.floatChannelData![channel][$0] }
        }
    }

    private func interleavedBuffer(_ samples: [Float], channels: Int) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                   channels: AVAudioChannelCount(channels), interleaved: true)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count / channels))!
        buffer.frameLength = AVAudioFrameCount(samples.count / channels)
        for sample in 0..<samples.count {
            buffer.floatChannelData![0][sample] = samples[sample]
        }
        return buffer
    }

    private func peak(_ buffer: AVAudioPCMBuffer) -> Float {
        samples(buffer).reduce(Float(0)) { max($0, abs($1)) }
    }

    func testQuietSpeechIsLiftedToTheTargetPeak() {
        let buffer = buffer([0, 0.02, -0.05, 0.03])
        SpeechLevelBoost.standard.amplify(buffer)
        XCTAssertEqual(peak(buffer), SpeechLevelBoost.targetPeak, accuracy: 0.001)
    }

    func testTheBoostStopsAtItsOwnMaximum() {
        let buffer = buffer([0, 0.01, -0.01])
        SpeechLevelBoost(maximumGain: 4).amplify(buffer)
        XCTAssertEqual(peak(buffer), 0.04, accuracy: 0.0001)
    }

    func testSpeechAtTheTargetOrLouderStaysUntouched() {
        let loud = buffer([0, 0.8, -0.6, 0.5])
        let before = samples(loud)
        SpeechLevelBoost.standard.amplify(loud)
        XCTAssertEqual(samples(loud), before)
    }

    func testSilenceAndRoomNoiseBelowTheFloorStayUntouched() {
        let silence = buffer([0, 0, 0, 0])
        let noise = buffer([0.001, -0.0015, 0.0005, 0])
        SpeechLevelBoost.standard.amplify(silence)
        SpeechLevelBoost.standard.amplify(noise)
        XCTAssertEqual(samples(silence), [0, 0, 0, 0])
        XCTAssertEqual(samples(noise), [0.001, -0.0015, 0.0005, 0])
    }

    func testTheBoostNeverLiftsThePeakAboveTheTarget() {
        for level in stride(from: Float(0.0021), through: 0.5, by: 0.02) {
            let buffer = buffer([0, level, -level])
            SpeechLevelBoost.standard.amplify(buffer)
            XCTAssertLessThanOrEqual(peak(buffer), SpeechLevelBoost.targetPeak + 0.0001)
        }
    }

    func testTheLoudestChannelDecidesTheGainForEveryChannel() {
        let stereo = buffer([0.1, 0.02, -0.1, 0.01], channels: 2)
        SpeechLevelBoost.standard.amplify(stereo)
        let expected: [Float] = [0.5, -0.5, 0.1, 0.05]
        for (index, value) in samples(stereo).enumerated() {
            XCTAssertEqual(value, expected[index], accuracy: 0.0001)
        }
    }

    func testAnInterleavedBufferIsBoostedAsAWhole() {
        let buffer = interleavedBuffer([0.1, 0.02, -0.1, 0.01], channels: 2)
        SpeechLevelBoost.standard.amplify(buffer)
        let expected: [Float] = [0.5, 0.1, -0.5, 0.05]
        for (index, value) in (0..<4).map({ buffer.floatChannelData![0][$0] }).enumerated() {
            XCTAssertEqual(value, expected[index], accuracy: 0.0001)
        }
    }

    func testAnInactiveBoostChangesNothing() {
        let buffer = buffer([0, 0.01, -0.02])
        let before = samples(buffer)
        SpeechLevelBoost.off.amplify(buffer)
        XCTAssertEqual(samples(buffer), before)
    }

    func testAnEmptyBufferIsIgnored() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let empty = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16)!
        SpeechLevelBoost.standard.amplify(empty)
        XCTAssertEqual(empty.frameLength, 0)
    }
}
