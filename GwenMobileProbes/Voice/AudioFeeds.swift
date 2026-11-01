@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import AVFoundation
import UIKit

final class AudioFileReader: @unchecked Sendable {
    let file: AVAudioFile
    let format: AVAudioFormat

    init(url: URL) throws {
        file = try AVAudioFile(forReading: url)
        format = file.processingFormat
    }

    func next(frames: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              (try? file.read(into: buffer, frameCount: frames)) != nil, buffer.frameLength > 0 else { return nil }
        return buffer
    }

    func silence(frames: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        return buffer
    }
}

@MainActor
final class FileAudioFeed: AudioFeeding {
    static let frames: AVAudioFrameCount = 4096

    private let url: URL
    private let trailingSilence: Double
    private var pump: Task<Void, Never>?
    private(set) var isRunning = false
    private(set) var spokenUntil: Date?

    init(url: URL, trailingSilence: Double) {
        self.url = url
        self.trailingSilence = trailingSilence
    }

    func start(deliver: @escaping @Sendable (AVAudioPCMBuffer) -> Void) async throws {
        let reader = try AudioFileReader(url: url)
        let silence = trailingSilence
        isRunning = true
        pump = Task { [weak self] in
            let step = Double(Self.frames) / reader.format.sampleRate
            while !Task.isCancelled, let buffer = reader.next(frames: Self.frames) {
                deliver(buffer)
                try? await Task.sleep(for: .seconds(Double(buffer.frameLength) / reader.format.sampleRate))
            }
            self?.spokenUntil = Date()
            var quiet = 0.0
            while !Task.isCancelled, quiet < silence, let buffer = reader.silence(frames: Self.frames) {
                deliver(buffer)
                try? await Task.sleep(for: .seconds(step))
                quiet += step
            }
        }
    }

    func stop() {
        pump?.cancel()
        pump = nil
        isRunning = false
    }
}

@MainActor
final class ScaledAudioFeed: AudioFeeding {
    private let inner: FileAudioFeed
    private let level: Float
    private let boost: SpeechLevelBoost

    init(url: URL, trailingSilence: Double, level: Float, boost: SpeechLevelBoost) {
        inner = FileAudioFeed(url: url, trailingSilence: trailingSilence)
        self.level = level
        self.boost = boost
    }

    var isRunning: Bool { inner.isRunning }
    var spokenUntil: Date? { inner.spokenUntil }

    func start(deliver: @escaping @Sendable (AVAudioPCMBuffer) -> Void) async throws {
        let level = self.level
        let boost = self.boost
        try await inner.start { buffer in
            Self.scale(buffer, to: level)
            boost.amplify(buffer)
            deliver(buffer)
        }
    }

    func stop() { inner.stop() }

    nonisolated private static func scale(_ buffer: AVAudioPCMBuffer, to level: Float) {
        guard level < 1, let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        for channel in 0..<Int(buffer.format.channelCount) {
            for frame in 0..<frames {
                channels[channel][frame] *= level
            }
        }
    }
}

@MainActor
final class HeardCommand {
    var text: String?
    var at: Date?
}
#endif
