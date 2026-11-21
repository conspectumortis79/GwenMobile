import AVFoundation
import Accelerate

struct SpeechLevelBoost: Equatable, Sendable {
    static let targetPeak: Float = 0.5
    static let noiseFloor: Float = 0.002
    static let standardGain: Float = 12
    static let standardSensitivity = 100
    static let sensitivityRange = 50...300

    let maximumGain: Float

    init(maximumGain: Float) {
        self.maximumGain = max(1, maximumGain)
    }

    init(sensitivityPercent: Int) {
        self.init(maximumGain: Self.standardGain * Float(Self.clampedSensitivity(sensitivityPercent))
            / Float(Self.standardSensitivity))
    }

    static func clampedSensitivity(_ percent: Int) -> Int {
        min(sensitivityRange.upperBound, max(sensitivityRange.lowerBound, percent))
    }

    #if DEBUG
    static let off = SpeechLevelBoost(maximumGain: 1)
    #endif
    static let standard = SpeechLevelBoost(sensitivityPercent: SpeechLevelBoost.standardSensitivity)

    var isActive: Bool { maximumGain > 1 }

    #if DEBUG
    func amplify(_ buffer: AVAudioPCMBuffer) {
        amplify(buffer, peak: Self.peak(of: buffer))
    }
    #endif

    func amplify(_ buffer: AVAudioPCMBuffer, peak: Float) {
        guard isActive, peak > Self.noiseFloor else { return }
        let gain = min(maximumGain, Self.targetPeak / peak)
        guard gain > 1 else { return }
        var factor = gain
        Self.forEachChannel(in: buffer) { channel, count in
            vDSP_vsmul(channel, 1, &factor, channel, 1, count)
        }
    }

    static func peak(of buffer: AVAudioPCMBuffer) -> Float {
        var found: Float = 0
        forEachChannel(in: buffer) { channel, count in
            var current: Float = 0
            vDSP_maxmgv(channel, 1, &current, count)
            found = max(found, current)
        }
        return found
    }

    private static func forEachChannel(in buffer: AVAudioPCMBuffer,
                                       _ body: (UnsafeMutablePointer<Float>, vDSP_Length) -> Void) {
        guard let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frames > 0, channelCount > 0 else { return }
        let interleaved = buffer.format.isInterleaved
        let pointers = interleaved ? 1 : channelCount
        let count = vDSP_Length(interleaved ? frames * channelCount : frames)
        for pointer in 0..<pointers {
            body(channels[pointer], count)
        }
    }
}
