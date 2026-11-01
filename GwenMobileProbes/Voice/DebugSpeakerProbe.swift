@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import AVFoundation
import Foundation

private final class MemoryProfileStore: SpeakerProfileStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var profile: SpeakerProfile?

    init(profile: SpeakerProfile?) {
        self.profile = profile
    }

    func load() -> SpeakerProfile? {
        lock.lock()
        defer { lock.unlock() }
        return profile
    }

    @discardableResult
    func save(_ profile: SpeakerProfile) -> Bool {
        lock.lock()
        self.profile = profile
        lock.unlock()
        return true
    }

    @discardableResult
    func delete() -> Bool {
        lock.lock()
        profile = nil
        lock.unlock()
        return true
    }
}

@MainActor
enum DebugSpeakerProbe {
    static let reportFile = "speaker.txt"
    static let sentence = "Die Sonne scheint über der alten Stadt und die Menschen gehen ruhig über den Marktplatz."

    static func run(_ view: ChatView) async {
        let report = SweepReport(file: reportFile)
        let embedder = SpeakerEmbedder()
        report.add("MODELL", "gebündelt=\(SpeakerEmbedder.isBundled) verfügbar=\(embedder.isAvailable) "
                   + "dimension=\(SpeakerProfile.dimension) profil=\(SpeakerProfileStore.shared.load()?.sampleCount ?? 0)")
        guard let german = AVSpeechSynthesisVoice(language: "de-DE") ?? VoiceCatalog.defaultVoice(for: .de),
              let english = AVSpeechSynthesisVoice(language: "en-US") ?? VoiceCatalog.defaultVoice(for: .en) else {
            report.add("STIMMEN", "ok=false keine_systemstimme")
            return
        }
        guard let first = await samples(voice: german), let second = await samples(voice: english) else {
            report.add("STIMMEN", "ok=false synthese_fehlgeschlagen")
            return
        }
        let firstEmbeddings = embeddings(first, embedder: embedder)
        let secondEmbeddings = embeddings(second, embedder: embedder)
        guard firstEmbeddings.count >= 2, secondEmbeddings.count >= 2,
              let profile = SpeakerProfileBuilder.profile(from: firstEmbeddings) else {
            report.add("STIMMEN", "ok=false fenster=\(firstEmbeddings.count)/\(secondEmbeddings.count)")
            return
        }
        let same = firstEmbeddings.map { profile.bestScore(for: $0) }.max() ?? -1
        let other = secondEmbeddings.map { profile.bestScore(for: $0) }.max() ?? -1
        report.add("STIMMEN", "gleich=\(format(same)) fremd=\(format(other)) "
                   + "fenster=\(firstEmbeddings.count)/\(secondEmbeddings.count) "
                   + "schwelle=\(format(profile.threshold(for: .normal)))")
        let store = MemoryProfileStore(profile: profile)
        let gate = SpeakerGate(embedder: embedder, store: store,
                               isEnabled: { true }, sensitivity: { .normal })
        gate.beginSession()
        feed(first, to: gate)
        let accepted = await gate.finalVerdict()
        gate.endSession()
        gate.beginSession()
        feed(second, to: gate)
        let refused = await gate.finalVerdict()
        gate.endSession()
        report.add("GATE", "eigene=\(accepted) fremd=\(refused) "
                   + "ok=\(accepted == .allowed && refused == .rejected)")
        flowLog.info("SPEAKER fertig")
    }

    private static func samples(voice: AVSpeechSynthesisVoice) async -> [Float]? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("speaker_\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let sink = SpeechFileSink(url: url)
        guard await SpeechFileProbe.synthesise(sentence, language: .de, voice: voice, into: sink) else {
            return nil
        }
        try? await Task.sleep(for: .milliseconds(400))
        guard let file = try? AVAudioFile(forReading: url), file.length > 0 else { return nil }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)) else { return nil }
        try? file.read(into: buffer)
        return SpeakerPCMConverter().samples(from: buffer)
    }

    private static func embeddings(_ samples: [Float], embedder: SpeakerEmbedder) -> [[Float]] {
        SpeakerAudioWindows.windows(from: samples).compactMap { embedder.embed($0) }
    }

    private static func feed(_ samples: [Float], to gate: SpeakerGate) {
        let format = SpeakerPCMConverter.format
        var start = 0
        while start < samples.count {
            let end = min(samples.count, start + 3200)
            let chunk = Array(samples[start..<end])
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                                frameCapacity: AVAudioFrameCount(chunk.count)),
                  let channel = buffer.floatChannelData?[0] else { return }
            for index in chunk.indices {
                channel[index] = chunk[index]
            }
            buffer.frameLength = AVAudioFrameCount(chunk.count)
            gate.worker.ingest(buffer)
            start = end
        }
    }

    private static func format(_ value: Float) -> String {
        String(format: "%.3f", value)
    }
}
#endif
