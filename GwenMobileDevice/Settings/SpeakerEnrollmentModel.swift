@testable import GwenMobileFeatureCore
import GwenMobileKit
import AVFoundation
import Combine
import Foundation

@MainActor
final class SpeakerEnrollmentModel: ObservableObject {
    enum Phase: Equatable {
        case ready
        case recording
        case analyzing
        case finished
        case failed(String)
    }

    static let recordingSeconds: TimeInterval = 5

    @Published private(set) var phase: Phase = .ready
    @Published private(set) var step = 0
    @Published private(set) var prompts: [String]
    @Published private(set) var embeddings: [[Float]] = []
    @Published private(set) var existing: SpeakerProfile?
    @Published private(set) var remaining = 0

    private let store: any SpeakerProfileStoring
    private let embedder: SpeakerEmbedder
    private let microphone: HeldMicrophone
    private var recordTask: Task<Void, Never>?

    init(store: any SpeakerProfileStoring = SpeakerProfileStore.shared,
         embedder: SpeakerEmbedder = SpeakerEmbedder(),
         microphone: HeldMicrophone = .shared) {
        self.store = store
        self.embedder = embedder
        self.microphone = microphone
        prompts = [
            L.t("speaker_enroll_prompt_1"),
            L.t("speaker_enroll_prompt_2"),
            L.t("speaker_enroll_prompt_3"),
        ]
        existing = store.load()
    }

    var isBusy: Bool { phase == .recording || phase == .analyzing }
    var isFinished: Bool { phase == .finished }
    var progress: Double { Double(step) / Double(prompts.count) }
    var currentPrompt: String { prompts[min(step, prompts.count - 1)] }

    func startStep() {
        guard !isBusy, step < prompts.count else { return }
        phase = .recording
        recordTask?.cancel()
        recordTask = Task { [weak self] in await self?.recordStep() }
    }

    func retry() {
        phase = .ready
        startStep()
    }

    func cancel() {
        recordTask?.cancel()
        recordTask = nil
        microphone.stop()
        if phase == .recording || phase == .analyzing {
            phase = .ready
        }
    }

    func finish() -> Bool {
        guard let profile = SpeakerProfileBuilder.profile(from: embeddings),
              store.save(profile) else { return false }
        existing = profile
        AppSettings.shared.voice.onlyMyVoice = true
        return true
    }

    func deleteProfile() {
        store.delete()
        existing = nil
        embeddings = []
        step = 0
        phase = .ready
        AppSettings.shared.voice.onlyMyVoice = false
    }

    private func recordStep() async {
        guard await microphoneAllowed() else {
            phase = .failed(L.t("mic_denied"))
            return
        }
        let collector = SpeakerSampleCollector()
        do {
            try await microphone.start { buffer in collector.append(buffer) }
        } catch {
            phase = .failed(L.t("mic_denied"))
            return
        }
        phase = .recording
        remaining = Int(Self.recordingSeconds)
        let started = Date()
        while Date().timeIntervalSince(started) < Self.recordingSeconds {
            if Task.isCancelled { break }
            remaining = max(0, Int(ceil(Self.recordingSeconds - Date().timeIntervalSince(started))))
            try? await Task.sleep(for: .milliseconds(100))
        }
        microphone.stop()
        remaining = 0
        guard !Task.isCancelled else {
            phase = .ready
            return
        }
        phase = .analyzing
        let samples = collector.samples()
        let windows = SpeakerAudioWindows.windows(from: samples)
        let embedder = self.embedder
        let found = await Offload.value {
            windows.compactMap { embedder.embed($0) }
        }
        guard found.count >= 2 else {
            phase = .failed(L.t("speaker_enroll_too_short"))
            return
        }
        if let consistency = SpeakerProfileBuilder.consistency(of: found), consistency < 0.35 {
            phase = .failed(L.t("speaker_enroll_inconsistent"))
            return
        }
        if !embeddings.isEmpty {
            let scores = found.map { candidate in
                embeddings.map { SpeakerProfileBuilder.cosine($0, candidate) }.max() ?? -1
            }
            let mean = scores.reduce(0, +) / Float(scores.count)
            guard mean >= 0.40 else {
                phase = .failed(L.t("speaker_enroll_inconsistent"))
                return
            }
        }
        embeddings.append(contentsOf: found.prefix(SpeakerProfileBuilder.maximumEmbeddings))
        if embeddings.count > SpeakerProfileBuilder.maximumEmbeddings {
            embeddings = Array(embeddings.prefix(SpeakerProfileBuilder.maximumEmbeddings))
        }
        step += 1
        phase = step >= prompts.count ? .finished : .ready
    }

    private func microphoneAllowed() async -> Bool {
        if VoiceMicrophonePort.allowed() { return true }
        return await withCheckedContinuation { continuation in
            VoiceMicrophonePort.request { granted in continuation.resume(returning: granted) }
        }
    }
}
