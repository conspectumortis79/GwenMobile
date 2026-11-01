@testable import GwenMobileFeatureCore
import AVFoundation
import Combine
import Foundation

@MainActor
protocol SpeakerGating: AnyObject {
    var isActive: Bool { get }
    var verdict: SpeakerVerdict { get }
    var onVerdict: ((SpeakerVerdict) -> Void)? { get set }
    func beginSession()
    func endSession()
    func finalVerdict() async -> SpeakerVerdict
}

@MainActor
final class SpeakerGate: ObservableObject, SpeakerGating, @unchecked Sendable {
    @Published private(set) var isActive = false
    @Published private(set) var verdict: SpeakerVerdict = .unknown
    var onVerdict: ((SpeakerVerdict) -> Void)?

    nonisolated let worker: SpeakerGateWorker
    private let embedder: SpeakerEmbedder
    private let store: any SpeakerProfileStoring
    private let isEnabled: @MainActor () -> Bool
    private let sensitivity: @MainActor () -> SpeakerSensitivity
    private var profile: SpeakerProfile?

    init(embedder: SpeakerEmbedder = SpeakerEmbedder.shared,
         store: any SpeakerProfileStoring = SpeakerProfileStore.shared,
         isEnabled: @escaping @MainActor () -> Bool = { AppSettings.shared.voice.onlyMyVoice },
         sensitivity: @escaping @MainActor () -> SpeakerSensitivity = {
             AppSettings.shared.voice.speakerSensitivity
         }) {
        self.embedder = embedder
        worker = SpeakerGateWorker(embedder: embedder)
        self.store = store
        self.isEnabled = isEnabled
        self.sensitivity = sensitivity
    }

    nonisolated func ingest(_ buffer: AVAudioPCMBuffer) {
        worker.ingest(buffer)
    }

    func beginSession() {
        guard isEnabled() else {
            worker.end()
            isActive = false
            verdict = .unknown
            profile = nil
            return
        }
        guard embedder.hasModel,
              let loaded = store.load(), !loaded.embeddings.isEmpty else {
            worker.end()
            isActive = true
            verdict = .rejected
            profile = nil
            return
        }
        profile = loaded
        isActive = true
        verdict = .unknown
        worker.begin(profile: loaded, threshold: loaded.threshold(for: sensitivity())) { [weak self] verdict in
            Task { @MainActor in self?.receive(verdict) }
        }
        let embedder = self.embedder
        Task.detached(priority: .userInitiated) {
            embedder.preload()
        }
    }

    func endSession() {
        worker.end()
        isActive = false
        verdict = .unknown
        profile = nil
    }

    func finalVerdict() async -> SpeakerVerdict {
        guard isActive else { return .allowed }
        guard profile != nil else { return .rejected }
        let result = await worker.finalVerdict()
        receive(result)
        return result
    }

    private func receive(_ verdict: SpeakerVerdict) {
        guard self.verdict != verdict else { return }
        self.verdict = verdict
        onVerdict?(verdict)
    }
}

final class SpeakerGateWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.mortis.gwenmobile.speaker-gate", qos: .userInitiated)
    private let converter = SpeakerPCMConverter()
    private let embedder: SpeakerEmbedder
    private let lock = NSLock()
    private var active = false
    private var profile: SpeakerProfile?
    private var threshold: Float = 0.55
    private var buffer: [Float] = []
    private var scores: [Float] = []
    private var lastAnalysis = Date.distantPast
    private var report: (@Sendable (SpeakerVerdict) -> Void)?

    init(embedder: SpeakerEmbedder) {
        self.embedder = embedder
    }

    func begin(profile: SpeakerProfile, threshold: Float,
               report: @escaping @Sendable (SpeakerVerdict) -> Void) {
        lock.lock()
        self.profile = profile
        self.threshold = threshold
        self.report = report
        buffer = []
        scores = []
        lastAnalysis = .distantPast
        active = true
        lock.unlock()
    }

    func end() {
        lock.lock()
        active = false
        profile = nil
        report = nil
        buffer = []
        scores = []
        lastAnalysis = .distantPast
        lock.unlock()
    }

    func ingest(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let running = active
        lock.unlock()
        guard running, let samples = converter.samples(from: buffer), !samples.isEmpty else { return }
        lock.lock()
        guard active else {
            lock.unlock()
            return
        }
        self.buffer.append(contentsOf: samples)
        let limit = SpeakerAudioWindows.sampleRate * 8
        if self.buffer.count > limit {
            self.buffer.removeFirst(self.buffer.count - limit)
        }
        let due = Date().timeIntervalSince(lastAnalysis) >= 0.75
        if due {
            lastAnalysis = Date()
        }
        lock.unlock()
        if due {
            queue.async { [weak self] in self?.analyze() }
        }
    }

    func finalVerdict() async -> SpeakerVerdict {
        await withCheckedContinuation { continuation in
            queue.async {
                self.lock.lock()
                guard self.active, let profile = self.profile else {
                    self.lock.unlock()
                    continuation.resume(returning: .rejected)
                    return
                }
                let suffix = Array(self.buffer.suffix(SpeakerAudioWindows.sampleRate * 4))
                let threshold = self.threshold
                self.lock.unlock()
                let windows = SpeakerAudioWindows.windows(from: suffix,
                                                          minimumSamples: SpeakerAudioWindows.sampleRate / 2)
                var found: [Float] = []
                for window in windows {
                    guard let embedding = self.embedder.embed(window) else { continue }
                    found.append(profile.bestScore(for: embedding))
                }
                let verdict = SpeakerScorePolicy.final(found, threshold: threshold)
                self.lock.lock()
                let report = self.report
                self.scores.append(contentsOf: found)
                self.lock.unlock()
                report?(verdict)
                continuation.resume(returning: verdict)
            }
        }
    }

    private func analyze() {
        lock.lock()
        guard active, let profile = self.profile else {
            lock.unlock()
            return
        }
        let window = Array(buffer.suffix(SpeakerAudioWindows.windowSamples))
        let threshold = self.threshold
        lock.unlock()
        guard let normalized = SpeakerAudioWindows.normalized(window),
              let embedding = embedder.embed(normalized) else { return }
        let score = profile.bestScore(for: embedding)
        lock.lock()
        guard active else {
            lock.unlock()
            return
        }
        scores.append(score)
        if scores.count > 6 {
            scores.removeFirst()
        }
        let verdict = SpeakerScorePolicy.early(scores, threshold: threshold)
        let report = self.report
        lock.unlock()
        report?(verdict)
    }
}
