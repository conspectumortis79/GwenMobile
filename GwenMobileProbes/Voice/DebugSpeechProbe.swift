@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import AVFoundation

final class SpeechFileSink: @unchecked Sendable {
    private let lock = NSLock()
    private let url: URL
    private var synthesizer: AVSpeechSynthesizer?
    private var file: AVAudioFile?
    private(set) var frames = 0
    private(set) var sampleRate = 0.0
    private(set) var failure: String?

    init(url: URL) {
        self.url = url
    }

    func keep(_ synthesizer: AVSpeechSynthesizer) {
        lock.lock()
        self.synthesizer = synthesizer
        lock.unlock()
    }

    func append(_ buffer: AVAudioBuffer) -> Bool {
        guard let pcm = buffer as? AVAudioPCMBuffer else { return false }
        lock.lock()
        defer { lock.unlock() }
        guard pcm.frameLength > 0 else { return true }
        do {
            if file == nil {
                file = try AVAudioFile(forWriting: url, settings: pcm.format.settings,
                                       commonFormat: pcm.format.commonFormat,
                                       interleaved: pcm.format.isInterleaved)
                sampleRate = pcm.format.sampleRate
            }
            try file?.write(from: pcm)
            frames += Int(pcm.frameLength)
        } catch {
            failure = error.localizedDescription
        }
        return false
    }

    func close() {
        lock.lock()
        file = nil
        synthesizer = nil
        lock.unlock()
    }
}

@MainActor
enum SpeechFileProbe {
    static let reportFile = "speech_file.txt"
    static let sentence = "Die Kernfusion verbindet leichte Atomkerne zu schwereren."
    static let synthesisTimeout: TimeInterval = 20

    static func run(_ view: ChatView) async {
        let report = SweepReport(file: reportFile)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("speech_probe.caf")
        try? FileManager.default.removeItem(at: url)
        let sink = SpeechFileSink(url: url)
        let synthesised = await synthesise(sentence, language: view.settings.language, into: sink)
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? -1
        report.add("DATEI", "fertig=\(synthesised) frames=\(sink.frames) rate=\(Int(sink.sampleRate)) bytes=\(bytes) "
                   + "fehler=\(sink.failure ?? "-")")
        let recognizer = SystemSpeechRecognizer(locale: view.settings.language.locale)
        report.add("ERKENNER", "status=\(SystemSpeechRecognizer.authorizationStatus.rawValue) "
                   + "verfuegbar=\(recognizer.isAvailable)")
        let started = ContinuousClock.now
        do {
            let text = try await recognizer.transcribe(wavURL: url)
            report.add("ERKENNUNG", "text=\(TextLine.oneLine(text, limit: 160)) ms=\(msOf(started.duration(to: .now))) "
                       + "kernfusion=\(text.lowercased().contains("kernfusion")) atomkerne=\(text.lowercased().contains("atomkerne"))")
        } catch {
            report.add("ERKENNUNG", "FEHLER \(error.localizedDescription) ms=\(msOf(started.duration(to: .now)))")
        }
        try? FileManager.default.removeItem(at: url)
        flowLog.info("SPEECHFILE fertig")
    }

    static func synthesise(_ text: String, language: AppLanguage, voice: AVSpeechSynthesisVoice? = nil,
                           into sink: SpeechFileSink,
                           timeout: TimeInterval = synthesisTimeout) async -> Bool {
        await synthesise([text], language: language, voice: voice, into: sink, timeout: timeout)
    }

    static func synthesise(_ texts: [String], language: AppLanguage, voice: AVSpeechSynthesisVoice? = nil,
                           into sink: SpeechFileSink,
                           timeout: TimeInterval = synthesisTimeout) async -> Bool {
        var complete = true
        for text in texts {
            let written = await write(text, language: language, voice: voice, into: sink, timeout: timeout)
            if !written { complete = false }
        }
        sink.close()
        return complete
    }

    private static func write(_ text: String, language: AppLanguage, voice: AVSpeechSynthesisVoice?,
                              into sink: SpeechFileSink,
                              timeout: TimeInterval) async -> Bool {
        let finished = LockedValue(false)
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let synthesizer = AVSpeechSynthesizer()
            sink.keep(synthesizer)
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voice ?? VoiceCatalog.defaultVoice(for: language)
            let watchdog = Task {
                try? await Task.sleep(for: .seconds(timeout))
                guard !finished.exchange(true) else { return }
                continuation.resume(returning: false)
            }
            synthesizer.write(utterance) { buffer in
                guard sink.append(buffer), !finished.exchange(true) else { return }
                watchdog.cancel()
                continuation.resume(returning: true)
            }
        }
    }
}
#endif
