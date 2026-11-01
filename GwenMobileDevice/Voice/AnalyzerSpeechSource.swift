@testable import GwenMobileFeatureCore
import GwenMobileKit
import AVFoundation
import Foundation
import Speech

@MainActor
final class LiveSpeechAnalysisSession: SpeechAnalysisSessioning {
    private let transcriber: SpeechTranscriber
    private let analyzer: SpeechAnalyzer
    private var reading: Task<Void, Never>?

    init(locale: Locale, reporting: Set<SpeechTranscriber.ReportingOption>) {
        transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                        reportingOptions: reporting, attributeOptions: [])
        analyzer = SpeechAnalyzer(modules: [transcriber])
    }

    func prepare(hints: [String]) async throws -> AVAudioFormat {
        try await AnalyzerSpeechSource.installModel(for: transcriber)
        let context = AnalysisContext()
        context.contextualStrings[.general] = hints
        try await analyzer.setContext(context)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw APIError(message: L.t("system_speech_unavailable"))
        }
        try await analyzer.prepareToAnalyze(in: format)
        return format
    }

    func start(input: AsyncStream<AnalyzerInput>) async throws -> AsyncThrowingStream<SpeechPiece, Error> {
        let (stream, continuation) = AsyncThrowingStream<SpeechPiece, Error>.makeStream()
        reading = Task {
            do {
                for try await result in transcriber.results {
                    continuation.yield(SpeechPiece(text: String(result.text.characters),
                                                   isFinal: result.isFinal))
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        do {
            try await analyzer.start(inputSequence: input)
        } catch {
            reading?.cancel()
            reading = nil
            continuation.finish(throwing: error)
            throw error
        }
        return stream
    }

    func finish() async throws {
        try await analyzer.finalizeAndFinishThroughEndOfInput()
    }

    func cancel() async {
        reading?.cancel()
        reading = nil
        await analyzer.cancelAndFinishNow()
    }
}

@MainActor
final class AnalyzerSpeechSource: FinalizingTranscribing {
    private let feed: any AudioFeeding
    private let isAvailable: @MainActor () -> Bool
    private let chooseLocale: @MainActor (Locale) async -> Locale?
    private let makeSession: @MainActor (Locale) -> any SpeechAnalysisSessioning
    private var session: (any SpeechAnalysisSessioning)?
    private var inputs: AsyncStream<AnalyzerInput>.Continuation?
    private var reading: Task<Void, Never>?
    private var cancellation: Task<Void, Never>?
    private var assembly = TranscriptAssembly()
    private var converter: AnalyzerFeed?
    private var results = 0
    private var began = Date()

    init(feed: any AudioFeeding,
         reporting: Set<SpeechTranscriber.ReportingOption> = [.volatileResults, .fastResults],
         isAvailable: @escaping @MainActor () -> Bool = { SpeechTranscriber.isAvailable },
         chooseLocale: @escaping @MainActor (Locale) async -> Locale? = { locale in
             await SpeechTranscriber.supportedLocale(equivalentTo: locale)
         },
         makeSession: (@MainActor (Locale) -> any SpeechAnalysisSessioning)? = nil) {
        self.feed = feed
        self.isAvailable = isAvailable
        self.chooseLocale = chooseLocale
        self.makeSession = makeSession ?? { locale in
            LiveSpeechAnalysisSession(locale: locale, reporting: reporting)
        }
    }

    let label = "speechanalyzer"
    #if DEBUG
    var isCapturing: Bool { feed.isRunning }
    #endif

    func start(locale: Locale, hints: [String],
               onText: @escaping @MainActor (String) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {
        if let cancellation {
            await cancellation.value
            self.cancellation = nil
        }
        guard isAvailable(),
              let chosen = await chooseLocale(locale) else {
            throw APIError(message: L.t("system_speech_unavailable"))
        }
        let session = makeSession(chosen)
        let format = try await session.prepare(hints: hints)
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let converter = AnalyzerFeed(target: format)
        self.converter = converter
        results = 0
        began = Date()
        flowMark("SPRACHE analyzer format=\(Int(format.sampleRate))hz kanaele=\(format.channelCount) "
                 + "art=\(format.commonFormat.rawValue)")
        let pieces = try await session.start(input: stream)
        self.session = session
        inputs = continuation
        assembly = TranscriptAssembly()
        reading = Task { [weak self] in
            do {
                for try await piece in pieces {
                    guard let self else { return }
                    self.results += 1
                    if self.results == 1 {
                        flowMark("SPRACHE analyzer erstes ergebnis ms=\(Int(Date().timeIntervalSince(self.began) * 1000))")
                    }
                    if piece.isFinal { self.assembly.settle(piece.text) } else { self.assembly.revise(piece.text) }
                    onText(self.assembly.text)
                }
            } catch is CancellationError {
                return
            } catch {
                onFailure(error.localizedDescription)
            }
        }
        try await feed.start(deliver: AnalyzerFeed.delivery(converter, into: continuation))
    }

    func stop() {
        if let converter {
            flowMark("SPRACHE analyzer ende \(converter.traceLine) ergebnisse=\(results)")
        }
        converter = nil
        feed.stop()
        inputs?.finish()
        inputs = nil
        reading?.cancel()
        reading = nil
        if let session {
            cancellation = Task { await session.cancel() }
        }
        session = nil
    }

    func settle() async -> String? {
        guard let session else { return nil }
        feed.stop()
        inputs?.finish()
        inputs = nil
        let reader = reading
        do {
            try await session.finish()
        } catch {
            flowMark("SPRACHE analyzer abschluss fehler=\(TextLine.oneLine(error.localizedDescription, limit: 80))")
        }
        await Self.settled(reader, within: 2)
        reading = nil
        self.session = nil
        flowMark("SPRACHE analyzer abschluss ergebnisse=\(results) zeichen=\(assembly.text.count)")
        return assembly.text
    }

    private static func settled(_ reader: Task<Void, Never>?, within seconds: Double) async {
        guard let reader else { return }
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(seconds))
            reader.cancel()
        }
        await reader.value
        watchdog.cancel()
    }

    nonisolated(unsafe) static var assetStatus: @MainActor (SpeechTranscriber) async -> AssetInventory.Status = { transcriber in
        await AssetInventory.status(forModules: [transcriber])
    }

    nonisolated(unsafe) static var installationRequest: @MainActor (SpeechTranscriber) async -> AssetInstallationRequest? = { transcriber in
        try? await AssetInventory.assetInstallationRequest(supporting: [transcriber])
    }

    static func installModel(for transcriber: SpeechTranscriber) async throws {
        guard await assetStatus(transcriber) != .installed else { return }
        flowMark("SPRACHE modell wird geladen")
        if let request = await installationRequest(transcriber) {
            try await request.downloadAndInstall()
        }
    }
}

final class AnalyzerFeed: @unchecked Sendable {
    private let target: AVAudioFormat
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var source: AVAudioFormat?
    private let counts = LockedValue((buffers: 0, empty: 0, frames: 0))

    var traceLine: String {
        let seen = counts.current
        lock.lock()
        let source = self.source
        lock.unlock()
        return "puffer=\(seen.buffers) leer=\(seen.empty) frames=\(seen.frames) "
            + "quelle=\(source.map { "\(Int($0.sampleRate))hz/\($0.commonFormat.rawValue)" } ?? "-")"
    }

    init(target: AVAudioFormat) {
        self.target = target
    }

    func converted(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        lock.lock()
        defer { lock.unlock() }
        if converter == nil || source != buffer.format {
            converter = AudioBufferConversion.makeConverter(from: buffer.format, to: target)
            source = buffer.format
        }
        guard let converter, buffer.frameLength > 0 else { return nil }
        guard let output = AudioBufferConversion.convert(buffer, to: target, using: converter) else {
            counts.mutate { seen in
                seen.buffers += 1
                seen.empty += 1
            }
            return nil
        }
        let frames = Int(output.frameLength)
        counts.mutate { seen in
            seen.buffers += 1
            seen.frames += frames
        }
        return output
    }

    static func delivery(_ feed: AnalyzerFeed, into continuation: AsyncStream<AnalyzerInput>.Continuation)
        -> @Sendable (AVAudioPCMBuffer) -> Void {
        { buffer in
            guard let converted = feed.converted(buffer) else { return }
            continuation.yield(AnalyzerInput(buffer: converted))
        }
    }
}
