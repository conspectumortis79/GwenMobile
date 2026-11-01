import GwenMobileKit
import Foundation

@MainActor
protocol LiveTranscribing: AnyObject {
    var label: String { get }
    #if DEBUG
    var isCapturing: Bool { get }
    #endif
    func start(locale: Locale, hints: [String],
               onText: @escaping @MainActor (String) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws
    func stop()
}

@MainActor
protocol FinalizingTranscribing: LiveTranscribing {
    func settle() async -> String?
}

@MainActor
final class PreferredSpeechSource: FinalizingTranscribing {
    private let candidates: [@MainActor () -> any LiveTranscribing]
    private var active: (any LiveTranscribing)?

    init(candidates: [@MainActor () -> any LiveTranscribing]) {
        self.candidates = candidates
    }

    var label: String { active?.label ?? "keine" }
    #if DEBUG
    var isCapturing: Bool { active?.isCapturing ?? false }
    #endif

    func start(locale: Locale, hints: [String],
               onText: @escaping @MainActor (String) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {
        var last: Error = APIError(message: L.t("system_speech_unavailable"))
        for make in candidates {
            let source = make()
            do {
                try await source.start(locale: locale, hints: hints, onText: onText, onFailure: onFailure)
                active = source
                flowMark("SPRACHE quelle=\(source.label)")
                return
            } catch {
                source.stop()
                last = error
                flowMark("SPRACHE quelle=\(source.label) fehlgeschlagen "
                         + TextLine.oneLine(error.localizedDescription, limit: 120))
            }
        }
        throw last
    }

    func settle() async -> String? {
        await (active as? any FinalizingTranscribing)?.settle()
    }

    func stop() {
        active?.stop()
        active = nil
    }
}

@MainActor
final class SilentSpeechSource: FinalizingTranscribing {
    #if DEBUG
    private(set) var isCapturing = false
    #endif
    let label = "stumm"

    func start(locale: Locale, hints: [String],
               onText: @escaping @MainActor (String) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {
        #if DEBUG
        isCapturing = true
        #endif
    }

    func stop() {
        #if DEBUG
        isCapturing = false
        #endif
    }
    func settle() async -> String? { nil }
}

@MainActor
enum VoiceSourcePort {
    nonisolated(unsafe) static var preferred: @MainActor (@escaping @MainActor () -> any AudioFeeding) -> any LiveTranscribing = { _ in
        SilentSpeechSource()
    }
}
