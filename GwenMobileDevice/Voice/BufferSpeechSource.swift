@testable import GwenMobileFeatureCore
import GwenMobileKit
import AVFoundation
import Foundation
import Speech

@MainActor
final class BufferSpeechSource: LiveTranscribing {
    nonisolated(unsafe) static var segmentLimit = Duration.seconds(50)
    static let failuresAllowed = 3

    private let feed: any AudioFeeding
    private let authorize: @MainActor () async throws -> Void
    private let slot = RequestSlot()
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private var rollover: Task<Void, Never>?
    private var assembly = TranscriptAssembly()
    private var hints: [String] = []
    private var onText: (@MainActor (String) -> Void)?
    private var onFailure: (@MainActor (String) -> Void)?
    private var segment = 0
    private var failuresInARow = 0

    init(feed: any AudioFeeding,
         authorize: @escaping @MainActor () async throws -> Void = {
             try await SystemSpeechRecognizer.authorize()
         }) {
        self.feed = feed
        self.authorize = authorize
    }

    let label = "sfspeech"
    #if DEBUG
    var isCapturing: Bool { feed.isRunning }
    #endif

    func start(locale: Locale, hints: [String],
               onText: @escaping @MainActor (String) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {
        try await authorize()
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw APIError(message: L.t("system_speech_unavailable"))
        }
        self.recognizer = recognizer
        self.hints = hints
        self.onText = onText
        self.onFailure = onFailure
        assembly = TranscriptAssembly()
        beginSegment()
        do {
            try await feed.start(deliver: RequestSlot.delivery(slot))
        } catch {
            stop()
            throw error
        }
        rollover = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.segmentLimit)
                guard !Task.isCancelled else { return }
                self?.nextSegment()
            }
        }
    }

    func stop() {
        rollover?.cancel()
        rollover = nil
        feed.stop()
        slot.current?.endAudio()
        slot.set(nil)
        task?.cancel()
        task = nil
        recognizer = nil
        segment += 1
    }

    private func beginSegment() {
        guard let recognizer else { return }
        segment += 1
        let mine = segment
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.contextualStrings = hints
        request.addsPunctuation = true
        slot.set(request)
        task = recognizer.recognitionTask(with: request, resultHandler: Self.handler { [weak self] heard in
            Task { @MainActor in self?.received(heard, segment: mine) }
        })
    }

    private func nextSegment() {
        guard recognizer != nil else { return }
        assembly.settlePending()
        slot.current?.endAudio()
        task?.cancel()
        beginSegment()
    }

    private func received(_ heard: HeardSegment, segment mine: Int) {
        guard mine == segment, recognizer != nil else { return }
        if let text = heard.text, !text.isEmpty {
            failuresInARow = 0
            if heard.final { assembly.settle(text) } else { assembly.revise(text) }
            onText?(assembly.text)
        }
        guard heard.final || heard.failure != nil else { return }
        if heard.failure != nil, !heard.silent { failuresInARow += 1 }
        guard failuresInARow < Self.failuresAllowed else {
            onFailure?(heard.failure ?? L.t("system_speech_unavailable"))
            return
        }
        nextSegment()
    }

    nonisolated private static func handler(_ forward: @escaping @Sendable (HeardSegment) -> Void)
        -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            forward(HeardSegment(text: result?.bestTranscription.formattedString, final: result?.isFinal ?? false,
                                 failure: error.map { $0.localizedDescription },
                                 silent: error.map { SystemSpeechRecognizer.reportsNoSpeech($0) } ?? false))
        }
    }
}
