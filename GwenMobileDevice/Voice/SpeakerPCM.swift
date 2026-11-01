@testable import GwenMobileFeatureCore
import AVFoundation
import Foundation

final class SpeakerPCMConverter: @unchecked Sendable {
    static let sampleRate: Double = 16000
    static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                      channels: 1, interleaved: false)!

    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?

    func samples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        guard buffer.frameLength > 0 else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if buffer.format == Self.format, let channel = buffer.floatChannelData?[0] {
            return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        }
        if converter == nil || sourceFormat != buffer.format {
            converter = AudioBufferConversion.makeConverter(from: buffer.format, to: Self.format)
            sourceFormat = buffer.format
        }
        guard let converter else { return nil }
        guard let output = AudioBufferConversion.convert(buffer, to: Self.format, using: converter),
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
