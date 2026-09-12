import Foundation
import AVFoundation

@MainActor
final class SpeechSynthesizer: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    static let outputSampleRate = 24_000
    static let audioTimeout: TimeInterval = 60
    static let localRate: Float = 0.5
    static let audioDeltaType = "response.audio.delta"
    static let responseDoneType = "response.done"

    @Published var isSpeaking = false

    private var player: AVAudioPlayer?
    private var speakTask: Task<Void, Never>?
    private var generation = 0
    private let remoteFinish = Flag(true)
    private var localSynth: AVSpeechSynthesizer?

    func speak(text: String, baseURL: String, key: String, model: String, voice: String) {
        let clean = Self.stripForSpeech(text)
        guard !clean.isEmpty else { return }
        stop()
        isSpeaking = true
        generation += 1
        let gen = generation
        if L.lang == .de, Self.systemGermanVoice != nil {
            speakLocal(clean)
            return
        }
        speakTask = Task { [weak self] in
            guard let self else { return }
            do {
                let pcm = try await Self.synthesize(text: clean, baseURL: baseURL, key: key,
                                                   model: model, voice: voice)
                let rate = Self.outputSampleRate
                let wav = try await Offload.run { WAVCodec.wav(fromPCM: pcm, sampleRate: rate) }
                guard !Task.isCancelled, gen == self.generation else {
                    if gen == self.generation { self.isSpeaking = false }
                    return
                }
                Self.routeToSpeaker()
                guard let player = try? AVAudioPlayer(data: wav) else {
                    self.speakLocal(clean)
                    return
                }
                player.delegate = self
                self.player = player
                self.remoteFinish.set(true)
                player.play()
            } catch {
                guard gen == self.generation, !Task.isCancelled else { return }
                self.speakLocal(clean)
            }
        }
    }

    func stop() {
        generation += 1
        remoteFinish.set(false)
        speakTask?.cancel()
        speakTask = nil
        player?.stop()
        player = nil
        localSynth?.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard remoteFinish.exchange(false) else { return }
        Task { @MainActor in
            self.player = nil
            self.isSpeaking = false
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }

    private func speakLocal(_ text: String) {
        player?.stop()
        player = nil
        remoteFinish.set(false)
        localSynth?.stopSpeaking(at: .immediate)
        let utter = AVSpeechUtterance(string: text)
        if L.lang != .de {
            utter.voice = Self.systemVoice(language: "en-US")
        } else if !AVSpeechSynthesisVoice.currentLanguageCode().hasPrefix("de") {
            utter.voice = Self.systemGermanVoice
        }
        utter.rate = Self.localRate
        utter.preUtteranceDelay = 0
        utter.postUtteranceDelay = 0
        let synth = AVSpeechSynthesizer()
        synth.delegate = self
        localSynth = synth
        Self.routeToSpeaker()
        synth.speak(utter)
    }

    static func systemVoice(language: String) -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice(language: language)
    }

    static var systemGermanVoice: AVSpeechSynthesisVoice? {
        systemVoice(language: "de-DE")
    }

    static var systemGermanVoiceName: String {
        systemGermanVoice?.name ?? "Deutsch"
    }

    static func stripForSpeech(_ text: String) -> String {
        var t = text
        t = t.replacingOccurrences(of: "```[\\s\\S]*?```", with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: "`([^`]*)`", with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\*{1,2}([^*]+)\\*{1,2}", with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: "^#{1,6}\\s*", with: "", options: [.regularExpression, .anchored])
        t = t.replacingOccurrences(of: "https?://\\S+", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func synthesize(text: String, baseURL: String, key: String,
                           model: String, voice: String) async throws -> Data {
        let timeoutMessage = L.t("tts_timeout")
        let emptyMessage = L.t("tts_empty")
        let prompt = L.t("tts_prefix") + text
        let deltaType = audioDeltaType
        let doneType = responseDoneType
        let timeout = audioTimeout
        return try await Offload.run {
            let client = try await RealtimeClient.opened(baseURL: baseURL, model: model, key: key,
                                                         timeoutMessage: timeoutMessage,
                                                         fallbackError: "TTS error")
            defer { client.close() }
            try await client.startSession([
                "modalities": ["text", "audio"],
                "voice": voice,
                "output_audio_format": "pcm",
                "turn_detection": NSNull(),
            ])
            try await client.send([
                "type": "conversation.item.create",
                "item": ["type": "message", "role": "user",
                         "content": [["type": "input_text", "text": prompt]]],
            ])
            try await client.send(["type": "response.create"])

            var pcm = Data()
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                let ev = try await client.receive(until: deadline)
                switch ev.type {
                case deltaType:
                    if let b64 = ev.delta, let d = Data(base64Encoded: b64) {
                        pcm.append(d)
                    }
                case doneType:
                    if !pcm.isEmpty { return pcm }
                    throw APIError(message: emptyMessage)
                case RealtimeClient.errorType:
                    throw APIError(message: ev.errorMessage ?? "TTS error")
                default:
                    break
                }
            }
            throw APIError(message: timeoutMessage)
        }
    }

    private static func routeToSpeaker() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.defaultToSpeaker])
        try? session.setActive(true)
    }
}
