@testable import GwenMobileFeatureCore
import AVFoundation
import Foundation

@MainActor
final class SpeakerAwareFeed: AudioFeeding {
    private let base: any AudioFeeding
    private let gate: SpeakerGate

    init(base: any AudioFeeding, gate: SpeakerGate) {
        self.base = base
        self.gate = gate
    }

    var isRunning: Bool { base.isRunning }
    #if DEBUG
    var isVoiceProcessing: Bool { base.isVoiceProcessing }
    #endif

    func start(deliver: @escaping @Sendable (AVAudioPCMBuffer) -> Void) async throws {
        let gate = self.gate
        try await base.start { buffer in
            gate.ingest(buffer)
            deliver(buffer)
        }
    }

    func stop() {
        base.stop()
    }

    func setVoiceProcessing(_ enabled: Bool) async throws {
        try await base.setVoiceProcessing(enabled)
    }
}
