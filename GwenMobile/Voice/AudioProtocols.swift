import AVFoundation
import Foundation

@MainActor
protocol AudioFeeding: AnyObject {
    var isRunning: Bool { get }
    func start(deliver: @escaping @Sendable (AVAudioPCMBuffer) -> Void) async throws
    func stop()
    func setVoiceProcessing(_ enabled: Bool) async throws
    #if DEBUG
    var isVoiceProcessing: Bool { get }
    #endif
}

@MainActor
extension AudioFeeding {
    func setVoiceProcessing(_ enabled: Bool) async throws {}
    #if DEBUG
    var isVoiceProcessing: Bool { false }
    #endif
}

@MainActor
protocol ResumableAudioFeeding: AudioFeeding {
    var isFlowing: Bool { get }
    func resume() async throws
    func reconnect() async throws
}

protocol AudioEngineing: AnyObject, Sendable {
    var isEngineRunning: Bool { get }
    func inputFormat() -> AVAudioFormat
    func installTap(bufferSize: AVAudioFrameCount, format: AVAudioFormat, block: @escaping AVAudioNodeTapBlock)
    func removeTap()
    func prepare()
    func start() throws
    func stop()
    func setVoiceProcessingEnabled(_ enabled: Bool) throws
}

extension AudioEngineing {
    func setVoiceProcessingEnabled(_ enabled: Bool) throws {}
}

@MainActor
final class StubAudioTap: ResumableAudioFeeding {
    private(set) var isRunning = false
    private(set) var isFlowing = false
    private var voiceProcessing = false

    func start(deliver: @escaping @Sendable (AVAudioPCMBuffer) -> Void) async throws {
        isRunning = true
        isFlowing = true
    }

    func stop() {
        isRunning = false
        isFlowing = false
    }

    func resume() async throws { isFlowing = true }
    func reconnect() async throws { isFlowing = true }
    func setVoiceProcessing(_ enabled: Bool) async throws { voiceProcessing = enabled }

    #if DEBUG
    var isVoiceProcessing: Bool { voiceProcessing }
    #endif
}

@MainActor
final class StubDisruptions: AudioDisruptionWatching {
    func start(_ handler: @escaping @MainActor (AudioDisruption) async -> Void) {}
    func stop() {}
}

@MainActor
final class StubHeadsets: HeadsetHandling {
    func start() {}
    func stop() {}
}

@MainActor
enum VoiceHardwarePort {
    nonisolated(unsafe) static var makeTap: @MainActor () -> any ResumableAudioFeeding = { StubAudioTap() }
    nonisolated(unsafe) static var makeDisruptions: @MainActor () -> any AudioDisruptionWatching = {
        StubDisruptions()
    }
    nonisolated(unsafe) static var makeHeadsets: @MainActor () -> any HeadsetHandling = { StubHeadsets() }
}
