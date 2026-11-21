import AVFoundation
import Foundation

final class SpeakerPCMConverter: @unchecked Sendable {
    static let sampleRate: Double = 16000
    static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                      channels: 1, interleaved: false)

    private let converter: LockedAudioConverter?

    init() {
        converter = Self.format.map(LockedAudioConverter.init(target:))
    }

    func samples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        guard buffer.frameLength > 0, let format = Self.format else { return nil }
        if buffer.format == format, let channel = buffer.floatChannelData?[0] {
            return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        }
        guard let output = converter?.convert(buffer),
              let channel = output.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}

final class SpeakerSampleCollector: @unchecked Sendable {
    private let converter = SpeakerPCMConverter()
    private let lock = NSLock()
    private var collected: [Float] = []

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let samples = converter.samples(from: buffer), !samples.isEmpty else { return }
        lock.lock()
        collected.append(contentsOf: samples)
        let limit = SpeakerAudioWindows.sampleRate * 7
        if collected.count > limit {
            collected.removeFirst(collected.count - limit)
        }
        lock.unlock()
    }

    func samples() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return collected
    }
}
