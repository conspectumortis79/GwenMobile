import GwenMobileKit
import AVFoundation
import Foundation
import Speech

@MainActor
final class BufferSpeechSource: FinalizingTranscribing, FeedBackedTranscribing {
    nonisolated(unsafe) static var segmentLimit = Duration.seconds(50)
    static let failuresAllowed = 3

    let feed: any AudioFeeding
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
    private var settleWaiter: CheckedContinuation<String?, Never>?
    private var settleDeadline: Task<Void, Never>?
    private var settling = false

    init(feed: any AudioFeeding,
         authorize: @escaping @MainActor () async throws -> Void = {
             try await SystemSpeechRecognizer.authorize()
         }) {
        self.feed = feed
        self.authorize = authorize
    }

    let label = "sfspeech"

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

    func settle() async -> String? {
        guard recognizer != nil else { return nil }
        guard settleWaiter == nil else { return assembly.text }
        settling = true
        rollover?.cancel()
        rollover = nil
        feed.stop()
        slot.current?.endAudio()
        slot.set(nil)
        return await withCheckedContinuation { (done: CheckedContinuation<String?, Never>) in
            settleWaiter = done
            settleDeadline = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled else { return }
                self.finishSettlement()
            }
        }
    }

    func stop() {
        finishSettlement()
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
        if settling {
            finishSettlement()
            return
        }
        if heard.failure != nil, !heard.silent { failuresInARow += 1 }
        guard failuresInARow < Self.failuresAllowed else {
            onFailure?(heard.failure ?? L.t("system_speech_unavailable"))
            return
        }
        nextSegment()
    }

    private func finishSettlement() {
        settleDeadline?.cancel()
        settleDeadline = nil
        settling = false
        task?.cancel()
        task = nil
        recognizer = nil
        guard let waiter = settleWaiter else { return }
        settleWaiter = nil
        waiter.resume(returning: assembly.text)
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
