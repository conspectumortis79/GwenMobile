@testable import GwenMobileFeatureCore
import GwenMobileKit
import AVFoundation
import Foundation

final class LiveAudioEngine: AudioEngineing, @unchecked Sendable {
    private let engine = AVAudioEngine()

    var isEngineRunning: Bool { engine.isRunning }

    func inputFormat() -> AVAudioFormat { engine.inputNode.inputFormat(forBus: 0) }

    func installTap(bufferSize: AVAudioFrameCount, format: AVAudioFormat,
                    block: @escaping AVAudioNodeTapBlock) {
        engine.inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format, block: block)
    }

    func removeTap() { engine.inputNode.removeTap(onBus: 0) }

    func prepare() { engine.prepare() }

    func start() throws { try engine.start() }

    func stop() { engine.stop() }

    func setVoiceProcessingEnabled(_ enabled: Bool) throws {
        try engine.inputNode.setVoiceProcessingEnabled(enabled)
    }
}

@MainActor
final class MicrophoneTap: ResumableAudioFeeding {
    static let bufferSize: AVAudioFrameCount = 4096

    private let engine: any AudioEngineing
    private let setups: [RecordingSetup]
    private var round = 0
    private var deliver: (@Sendable (AVAudioPCMBuffer) -> Void)?
    private(set) var isRunning = false
    private(set) var voiceProcessing = false

    init(setups: [RecordingSetup] = RecordingSetup.preferred,
         engine: any AudioEngineing = LiveAudioEngine()) {
        self.setups = setups
        self.engine = engine
    }

    var prepareSession: @MainActor (RecordingSetup) async throws -> Void = { setup in
        try await AudioSessionSetup.prepare(.playAndRecord, mode: setup.mode, options: setup.options)
    }

    var isFlowing: Bool { isRunning && engine.isEngineRunning }
    #if DEBUG
    var isVoiceProcessing: Bool { voiceProcessing }
    #endif

    func start(deliver: @escaping @Sendable (AVAudioPCMBuffer) -> Void) async throws {
        AudioRound.recording.mutate { round in
            round += 1
        }
        round = AudioRound.recording.current
        do {
            try await run(deliver)
        } catch {
            detachEngine()
            release()
            throw error
        }
        self.deliver = deliver
        isRunning = true
        AudioRound.capturing.mutate { count in
            count += 1
        }
    }

    func resume() async throws {
        guard isRunning, let deliver else { return }
        detachEngine()
        try await run(deliver)
    }

    func reconnect() async throws {
        guard isRunning, let deliver else { return }
        detachEngine()
        do {
            try await tapAndStart(deliver, label: "neu_verbunden")
        } catch {
            detachEngine()
            throw error
        }
    }

    func setVoiceProcessing(_ enabled: Bool) async throws {
        guard voiceProcessing != enabled else { return }
        voiceProcessing = enabled
        guard isRunning, let deliver else { return }
        detachEngine()
        do {
            try await run(deliver)
        } catch {
            stop()
            voiceProcessing = !enabled
            throw error
        }
    }

    func stop() {
        detachEngine()
        if isRunning {
            isRunning = false
            AudioRound.capturing.mutate { count in
                count = max(0, count - 1)
            }
        }
        deliver = nil
        release()
    }

    private func run(_ deliver: @escaping @Sendable (AVAudioPCMBuffer) -> Void) async throws {
        var failure: Error = APIError(message: L.t("mic_unavailable"))
        for setup in setups {
            do {
                try await attempt(deliver, in: setup)
                return
            } catch {
                detachEngine()
                flowMark("MIKRO modus=\(setup.label) abgelehnt code=\((error as NSError).code)")
                failure = error
            }
        }
        throw failure
    }

    private func attempt(_ deliver: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
                         in setup: RecordingSetup) async throws {
        let sessionStart = ContinuousClock.now
        try await prepareSession(setup)
        flowMarkPersonal("MIKRO sitzung ms=\(msOf(sessionStart.duration(to: .now)))")
        let engineStart = ContinuousClock.now
        try await tapAndStart(deliver, label: setup.label)
        flowMarkPersonal("MIKRO motor ms=\(msOf(engineStart.duration(to: .now)))")
    }

    private func tapAndStart(_ deliver: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
                             label: String) async throws {
        let format = try await AudioEngineSetup.start(engine, bufferSize: Self.bufferSize,
                                                      voiceProcessing: voiceProcessing,
                                                      block: Self.tap(deliver))
        flowMarkPersonal("MIKRO weg modus=\(label) hz=\(Int(format.sampleRate)) " + MicrophoneRoute.current())
    }

    private func detachEngine() {
        AudioEngineSetup.stop(engine)
    }

    private func release() {
        let round = self.round
        Task { await AudioRoute.shared.endRecording(atRound: round) }
    }

    nonisolated private static func tap(_ deliver: @escaping @Sendable (AVAudioPCMBuffer) -> Void)
        -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { buffer, _ in deliver(buffer) }
    }
}

enum AudioEngineSetup {
    private static let queue = DispatchQueue(label: "com.mortis.gwenmobile.audio-engine")

    static func start(_ engine: any AudioEngineing, bufferSize: AVAudioFrameCount,
                      voiceProcessing: Bool = false,
                      block: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void) async throws
        -> AVAudioFormat {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AVAudioFormat, Error>) in
            queue.async {
                var installed = false
                do {
                    if voiceProcessing {
                        do {
                            try engine.setVoiceProcessingEnabled(true)
                        } catch {
                            throw APIError(message: L.t("echo_failed"))
                        }
                    } else {
                        try? engine.setVoiceProcessingEnabled(false)
                    }
                    let format = engine.inputFormat()
                    guard format.sampleRate > 0, format.channelCount > 0 else {
                        throw APIError(message: L.t("mic_unavailable"))
                    }
                    engine.removeTap()
                    engine.installTap(bufferSize: bufferSize, format: format, block: block)
                    installed = true
                    engine.prepare()
                    try engine.start()
                    continuation.resume(returning: format)
                } catch {
                    if installed { engine.removeTap() }
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func stop(_ engine: any AudioEngineing) {
        queue.async {
            engine.removeTap()
            engine.stop()
        }
    }
}

enum AudioSessionSetup {
    private static let queue = DispatchQueue(label: "com.mortis.gwenmobile.audio-session")

    static func prepare(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode,
                        options: AVAudioSession.CategoryOptions) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(category, mode: mode, options: options)
                    try session.setActive(true)
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
