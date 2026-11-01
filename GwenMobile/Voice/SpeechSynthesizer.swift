import GwenMobileKit
import Foundation
import AVFoundation

@MainActor
final class SpeechSynthesizer: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let localRate: Float = 0.5
    static var makeEngine: () -> AVSpeechSynthesizer = { AVSpeechSynthesizer() }

    private static let variant = try? NSRegularExpression(pattern: ".\u{FE0F}")
    private static let fencedCode = try? NSRegularExpression(pattern: "```[\\s\\S]*?```")
    private static let inlineCode = try? NSRegularExpression(pattern: "`([^`]*)`")
    private static let emphasis = try? NSRegularExpression(pattern: "\\*{1,2}([^*]+)\\*{1,2}")
    private static let heading = try? NSRegularExpression(pattern: "^#{1,6}[ \\t]*", options: [.anchorsMatchLines])
    private static let link = try? NSRegularExpression(pattern: "\\[([^\\]\\n]{1,200})\\]\\([^)\\s]{1,500}\\)")
    private static let url = try? NSRegularExpression(pattern: "https?://\\S+")
    private static let spaces = try? NSRegularExpression(pattern: "\\s{2,}")

    @Published var isSpeaking = false

    private var synthesizer: AVSpeechSynthesizer?
    private var playbackRound: Int?
    private var routeStarting = false
    private var waiting: [AVSpeechUtterance] = []
    private var pending = 0
    private var streamBuffer = ""
    private var streaming = false
    private var streamSuppressed = false
    private var streamedSinceAnswer = false
    private var streamVoice = VoiceOption.systemDefaultID

    func speak(text: String, voiceIdentifier: String = VoiceOption.systemDefaultID) {
        let clean = Self.stripForSpeech(text)
        guard !clean.isEmpty else { return }
        discardCurrentPlayback()
        enqueue(clean, voiceIdentifier: voiceIdentifier)
    }

    func beginStream(voiceIdentifier: String) {
        streaming = true
        streamSuppressed = false
        streamBuffer = ""
        streamedSinceAnswer = false
        streamVoice = voiceIdentifier
    }

    func stream(_ chunk: String) {
        guard streaming, !streamSuppressed else { return }
        streamBuffer += chunk
        guard !streamBuffer.contains(SearchMarker.token) else {
            streamSuppressed = true
            streamBuffer = ""
            discardCurrentPlayback()
            streaming = true
            return
        }
        for sentence in SpeechSentences.take(from: &streamBuffer) {
            let clean = Self.stripForSpeech(sentence)
            guard !clean.isEmpty else { continue }
            streamedSinceAnswer = true
            flowMark("VORLESEN satz=\(TextLine.oneLine(clean, limit: 60))")
            enqueue(clean, voiceIdentifier: streamVoice)
        }
    }

    func endStream() {
        guard streaming else { return }
        streaming = false
        guard !streamSuppressed else {
            streamBuffer = ""
            return
        }
        let rest = streamBuffer
        streamBuffer = ""
        let clean = Self.stripForSpeech(rest)
        guard !clean.isEmpty else { return }
        streamedSinceAnswer = true
        flowMark("VORLESEN rest=\(TextLine.oneLine(clean, limit: 60))")
        enqueue(clean, voiceIdentifier: streamVoice)
    }

    func takeStreamed() -> Bool {
        let spoken = streamedSinceAnswer
        streamedSinceAnswer = false
        return spoken
    }

    func stop() {
        discardCurrentPlayback()
    }

    private func enqueue(_ clean: String, voiceIdentifier: String) {
        guard let synth = synthesizer ?? makeSynthesizer() else { return }
        let utterance = AVSpeechUtterance(string: clean)
        utterance.voice = VoiceCatalog.voice(identifier: voiceIdentifier, language: L.lang)
        utterance.rate = Self.localRate
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0
        isSpeaking = true
        if playbackRound != nil {
            pending += 1
            synth.speak(utterance)
            return
        }
        waiting.append(utterance)
        guard !routeStarting else { return }
        routeStarting = true
        Task { [weak self] in
            guard let self else { return }
            let round = await AudioRoute.shared.startPlayback()
            guard self.synthesizer === synth else {
                self.routeStarting = false
                self.waiting = []
                await AudioRoute.shared.endPlayback(atRound: round)
                return
            }
            self.playbackRound = round
            self.routeStarting = false
            let starting = self.waiting
            self.waiting = []
            for item in starting {
                self.pending += 1
                synth.speak(item)
            }
        }
    }

    private func makeSynthesizer() -> AVSpeechSynthesizer? {
        let made = Self.makeEngine()
        made.delegate = self
        synthesizer = made
        return made
    }

    private func discardCurrentPlayback() {
        let synth = synthesizer
        synthesizer = nil
        isSpeaking = false
        streaming = false
        streamBuffer = ""
        streamedSinceAnswer = false
        routeStarting = false
        waiting = []
        pending = 0
        synth?.stopSpeaking(at: .immediate)
        guard let round = playbackRound else { return }
        playbackRound = nil
        Task { await AudioRoute.shared.endPlayback(atRound: round) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        ended(synthesizer)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        ended(synthesizer)
    }

    private nonisolated func ended(_ synth: AVSpeechSynthesizer) {
        let key = ObjectIdentifier(synth)
        let stillSpeaking = synth.isSpeaking
        Task { @MainActor [weak self] in
            guard let self, self.synthesizer.map(ObjectIdentifier.init) == key else { return }
            self.pending = max(0, self.pending - 1)
            guard self.pending == 0 || !stillSpeaking else { return }
            self.synthesizer = nil
            self.isSpeaking = false
            self.routeStarting = false
            self.waiting = []
            guard let round = self.playbackRound else { return }
            self.playbackRound = nil
            await AudioRoute.shared.endPlayback(atRound: round)
        }
    }

    static func stripForSpeech(_ text: String) -> String {
        var t = replacing(in: text, with: variant, template: "")
        t = String(t.unicodeScalars.filter { scalar in
            let value = scalar.value
            if value == 0xFE0F || value == 0x200D { return false }
            if (0x2190...0x2BFF).contains(value) { return false }
            if scalar.properties.isEmojiPresentation || scalar.properties.isEmojiModifier { return false }
            if scalar.properties.isEmoji && value >= 0x1F000 { return false }
            return true
        })
        t = replacing(in: t, with: fencedCode, template: " ")
        t = CitationMarkers.stripped(from: t)
        t = replacing(in: t, with: inlineCode, template: "$1")
        t = replacing(in: t, with: emphasis, template: "$1")
        t = replacing(in: t, with: heading, template: "")
        t = replacing(in: t, with: link, template: "$1")
        t = replacing(in: t, with: url, template: "")
        t = replacing(in: t, with: spaces, template: " ")
        return t.trimmed
    }

    private static func replacing(in text: String, with regex: NSRegularExpression?,
                                  template: String) -> String {
        guard let regex else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                              withTemplate: template)
    }
}
