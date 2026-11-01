import GwenMobileKit
import AVFoundation

enum AudioBufferConversion {
    static func makeConverter(from source: AVAudioFormat, to target: AVAudioFormat) -> AVAudioConverter? {
        guard let converter = AVAudioConverter(from: source, to: target) else { return nil }
        if source.channelCount > target.channelCount {
            converter.channelMap = (0..<Int(target.channelCount)).map { NSNumber(value: $0) }
        }
        return converter
    }

    static func convert(_ buffer: AVAudioPCMBuffer, to target: AVAudioFormat,
                        using converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        let handed = LockedValue(false)
        var failure: NSError?
        let status = converter.convert(to: output, error: &failure) { _, state in
            if handed.exchange(true) {
                state.pointee = .noDataNow
                return nil
            }
            state.pointee = .haveData
            return buffer
        }
        guard status != .error, output.frameLength > 0 else { return nil }
        return output
    }
}
