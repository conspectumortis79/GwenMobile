import AVFoundation
import Accelerate

struct SpeechLevelBoost: Equatable, Sendable {
    static let targetPeak: Float = 0.5
    static let noiseFloor: Float = 0.002

    let maximumGain: Float

    init(maximumGain: Float) {
        self.maximumGain = max(1, maximumGain)
    }

    #if DEBUG
    static let off = SpeechLevelBoost(maximumGain: 1)
    #endif
    static let standard = SpeechLevelBoost(maximumGain: 12)

    var isActive: Bool { maximumGain > 1 }

    #if DEBUG
    func amplify(_ buffer: AVAudioPCMBuffer) {
        amplify(buffer, peak: Self.peak(of: buffer))
    }
    #endif

    func amplify(_ buffer: AVAudioPCMBuffer, peak: Float) {
        guard isActive, let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frames > 0, channelCount > 0 else { return }
        let interleaved = buffer.format.isInterleaved
        let pointers = interleaved ? 1 : channelCount
        let count = interleaved ? frames * channelCount : frames
        guard peak > Self.noiseFloor else { return }
        let gain = min(maximumGain, Self.targetPeak / peak)
        guard gain > 1 else { return }
        var factor = gain
        for pointer in 0..<pointers {
            vDSP_vsmul(channels[pointer], 1, &factor, channels[pointer], 1, vDSP_Length(count))
        }
    }

    static func peak(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frames > 0, channelCount > 0 else { return 0 }
        let interleaved = buffer.format.isInterleaved
        let pointers = interleaved ? 1 : channelCount
        let count = interleaved ? frames * channelCount : frames
        var found: Float = 0
        for pointer in 0..<pointers {
            var current: Float = 0
            vDSP_maxmgv(channels[pointer], 1, &current, vDSP_Length(count))
            found = max(found, current)
        }
        return found
    }
}
