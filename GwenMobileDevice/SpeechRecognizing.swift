@testable import GwenMobileFeatureCore
import GwenMobileKit
import Foundation
import Speech

final class SystemSpeechRecognizer: @unchecked Sendable {
    static func reportsNoSpeech(_ error: Error) -> Bool {
        error.localizedDescription.lowercased().contains("no speech")
    }

    nonisolated(unsafe) static var authorizationStatusOverride: SFSpeechRecognizerAuthorizationStatus?
    nonisolated(unsafe) static var requestAuthorization: @Sendable () async -> Bool = {
        await SystemSpeechRecognizer.requestAuthorizationLive()
    }

    static func requestAuthorizationLive() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }

    static func authorize() async throws {
        switch authorizationStatus {
        case .authorized:
            return
        case .notDetermined:
            let granted = await requestAuthorization()
            guard granted else { throw APIError(message: L.t("speech_recognition_denied")) }
        default:
            throw APIError(message: L.t("speech_recognition_denied"))
        }
    }

    static var authorizationStatus: SFSpeechRecognizerAuthorizationStatus {
        authorizationStatusOverride ?? SFSpeechRecognizer.authorizationStatus()
    }

    #if DEBUG
    protocol SpeechTasking: AnyObject {
        func cancel()
    }

    final class LiveSpeechTask: SpeechTasking {
        private let task: SFSpeechRecognitionTask

        init(_ task: SFSpeechRecognitionTask) { self.task = task }

        func cancel() { task.cancel() }
    }

    private let recognizer: SFSpeechRecognizer?
    private let timeout: TimeInterval
    private let lock = NSLock()
    private var running: (any SpeechTasking)?

    static let defaultTimeout: TimeInterval = 15

    var makeRequest: (URL) -> SFSpeechURLRecognitionRequest = { url in
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        return request
    }

    var startTask: (SFSpeechRecognizer, SFSpeechURLRecognitionRequest,
                    @escaping (String?, Bool, Error?) -> Void) -> any SpeechTasking = { recognizer, request, handler in
        let task = recognizer.recognitionTask(with: request) { result, error in
            handler(result?.bestTranscription.formattedString, result?.isFinal ?? false, error)
        }
        return LiveSpeechTask(task)
    }

    init(locale: Locale, timeout: TimeInterval = SystemSpeechRecognizer.defaultTimeout) {
        recognizer = SFSpeechRecognizer(locale: locale)
        self.timeout = timeout
    }

    var isAvailableOverride: Bool?

    var isAvailable: Bool { isAvailableOverride ?? (recognizer?.isAvailable ?? false) }

    func transcribe(wavURL: URL) async throws -> String {
        try await Self.authorize()
        return try await transcribeAuthorized(wavURL: wavURL)
    }

    func transcribeAuthorized(wavURL: URL) async throws -> String {
        guard let recognizer, recognizer.isAvailable else {
            throw APIError(message: L.t("system_speech_unavailable"))
        }
        let request = makeRequest(wavURL)
        let answer = LockedValue<(@Sendable (Result<String, Error>) -> Void)?>(nil)
        let timeoutMessage = L.t("asr_timeout")
        let watchdog = Task { [weak self, timeout] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            self?.cancelRunning()
            answer.current?(.failure(APIError(message: timeoutMessage)))
        }
        defer { watchdog.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            let resumed = LockedValue(false)
            answer.set { result in
                guard !resumed.exchange(true) else { return }
                continuation.resume(with: result)
            }
            let task = startTask(recognizer, request) { text, isFinal, error in
                Self.receive(text: text, isFinal: isFinal, error: error,
                             answer: answer) { Self.reportsNoSpeech($0) }
            }
            remember(task)
        }
    }

    nonisolated static func receive(text: String?, isFinal: Bool, error: Error?,
                                    answer: LockedValue<(@Sendable (Result<String, Error>) -> Void)?>,
                                    isNoSpeech: (Error) -> Bool) {
        if let error {
            if isNoSpeech(error) {
                answer.current?(.success(""))
            } else {
                answer.current?(.failure(error))
            }
            return
        }
        guard isFinal else { return }
        answer.current?(.success(text ?? ""))
    }

    private func remember(_ task: any SpeechTasking) {
        lock.lock()
        running = task
        lock.unlock()
    }

    private func cancelRunning() {
        lock.lock()
        let task = running
        running = nil
        lock.unlock()
        task?.cancel()
    }
    #endif
}
