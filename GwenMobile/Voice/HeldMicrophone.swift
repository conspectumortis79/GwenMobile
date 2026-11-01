import GwenMobileKit
import AVFoundation
import Foundation

@MainActor
final class HeldMicrophone: ObservableObject, AudioFeeding {
    static let shared = HeldMicrophone(tap: VoiceHardwarePort.makeTap(),
                                       disruptions: VoiceHardwarePort.makeDisruptions(),
                                       headsets: VoiceHardwarePort.makeHeadsets())

    @Published private(set) var isLive = false
    @Published private(set) var engineRecoveries = 0
    private(set) var isHeld = false

    private let tap: any ResumableAudioFeeding
    private let disruptions: any AudioDisruptionWatching
    private let headsets: any HeadsetHandling
    private let boost: SpeechLevelBoost
    private let target = LockedValue<(@Sendable (AVAudioPCMBuffer) -> Void)?>(nil)
    private let delivered = LockedValue(0)
    #if DEBUG
    private let peak = LockedValue<Float>(0)
    #endif
    private let meter = AudioLevelMeter()
    private var attached = false
    private var recovering = false
    private var startTask: Task<Void, Error>?
    private var onLoss: (@MainActor () -> Void)?

    init(tap: any ResumableAudioFeeding, disruptions: any AudioDisruptionWatching, headsets: any HeadsetHandling,
         boost: SpeechLevelBoost = .standard) {
        self.tap = tap
        self.disruptions = disruptions
        self.headsets = headsets
        self.boost = boost
    }

    var isRunning: Bool { attached && tap.isRunning }
    #if DEBUG
    var isVoiceProcessing: Bool { tap.isVoiceProcessing }
    var buffersDelivered: Int { delivered.current }
    var currentPeak: Float { peak.current }
    #endif

    func start(deliver: @escaping @Sendable (AVAudioPCMBuffer) -> Void) async throws {
        target.set(deliver)
        attached = true
        if let startTask {
            try await startTask.value
            return
        }
        guard !tap.isRunning else { return }
        let task = Task {
            try await tap.start(deliver: Self.forward(to: target, counting: delivered, measuring: measuring,
                                                      boosting: boost))
        }
        startTask = task
        do {
            try await task.value
        } catch {
            startTask = nil
            detach()
            throw error
        }
        startTask = nil
        guard attached else {
            tap.stop()
            return
        }
        isLive = true
        disruptions.start { [weak self] disruption in await self?.handle(disruption) }
        headsets.start()
        flowMark("MIKRO an gehalten=\(isHeld)")
    }

    func stop() {
        detach()
        guard !isHeld else { return }
        shutDown()
    }

    func setVoiceProcessing(_ enabled: Bool) async throws {
        try await tap.setVoiceProcessing(enabled)
    }

    func hold(onLoss: @escaping @MainActor () -> Void) {
        isHeld = true
        self.onLoss = onLoss
        flowMark("MIKRO halten läuft=\(tap.isRunning)")
    }

    func release() {
        isHeld = false
        onLoss = nil
        flowMark("MIKRO loslassen angehaengt=\(attached)")
        guard !attached else { return }
        shutDown()
    }

    private func detach() {
        target.set(nil)
        attached = false
    }

    private func shutDown() {
        guard tap.isRunning || isLive else { return }
        disruptions.stop()
        headsets.stop()
        tap.stop()
        isLive = false
        flowMark("MIKRO aus puffer=\(delivered.current)")
    }

    private func handle(_ disruption: AudioDisruption) async {
        guard disruption != .began, tap.isRunning, !tap.isFlowing, !recovering else { return }
        recovering = true
        defer { recovering = false }
        var failure: Error?
        for recovery in recoveries(after: disruption) {
            do {
                try await recovery()
                flowMark("MIKRO fortgesetzt art=\(disruption)")
                engineRecoveries += 1
                return
            } catch {
                failure = error
            }
        }
        let reason = failure!.localizedDescription
        let code = (failure! as NSError).code
        flowMark("MIKRO verloren " + TextLine.oneLine(reason, limit: 120) + " code=\(code)")
        lose()
    }

    private func recoveries(after disruption: AudioDisruption) -> [() async throws -> Void] {
        let tap = self.tap
        let resume: () async throws -> Void = { try await tap.resume() }
        guard disruption == .reconfigured else { return [resume] }
        return [{ try await tap.reconnect() }, resume]
    }

    private func lose() {
        let report = onLoss
        detach()
        shutDown()
        report?()
    }

    private var measuring: @Sendable (Float) -> Void {
        let meter = self.meter
        #if DEBUG
        let peak = self.peak
        return { level in
            peak.set(level)
            meter.measure(peak: level)
        }
        #else
        return { level in meter.measure(peak: level) }
        #endif
    }

    nonisolated private static func forward(to target: LockedValue<(@Sendable (AVAudioPCMBuffer) -> Void)?>,
                                            counting delivered: LockedValue<Int>,
                                            measuring: @escaping @Sendable (Float) -> Void,
                                            boosting boost: SpeechLevelBoost)
        -> @Sendable (AVAudioPCMBuffer) -> Void {
        { buffer in
            delivered.mutate { count in
                count += 1
            }
            let peak = SpeechLevelBoost.peak(of: buffer)
            measuring(peak)
            boost.amplify(buffer, peak: peak)
            target.current?(buffer)
        }
    }
}
