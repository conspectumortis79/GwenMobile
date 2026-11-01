import GwenMobileKit
import Foundation

struct VoiceSignals: Equatable, Sendable {
    let wake: SignalPhrase
    let stop: SignalPhrase
    let cancel: SignalPhrase
    let newChat: [SignalPhrase]
    let listenOff: [SignalPhrase]
    let hints: [String]

    init(wake: String, stop: String, cancel: String, newChat: String = "", listenOff: String = "") {
        self.wake = SignalPhrase(wake)
        self.stop = SignalPhrase(stop)
        self.cancel = SignalPhrase(cancel)
        self.newChat = SignalPhrase.alternatives(newChat)
        self.listenOff = SignalPhrase.alternatives(listenOff)
        let spoken = [wake, stop, cancel] + [newChat, listenOff].flatMap {
            $0.components(separatedBy: SignalPhrase.alternativeMarks)
        }
        hints = spoken.map { $0.trimmed }.filter { !$0.isEmpty }
    }

    static let none = VoiceSignals(wake: "", stop: "", cancel: "")
}

struct HeardWake: Equatable {
    let anchor: Int
    let request: String
}

struct WakeAnchor: Equatable {
    private(set) var position = 0
    private(set) var revised = false

    mutating func request(in transcript: String, wake: SignalPhrase) -> String? {
        if let heard = VoiceCommand.heardWake(in: transcript, wake: wake) {
            position = heard.anchor
            return heard.request
        }
        guard let request = VoiceCommand.request(in: transcript, from: position) else { return nil }
        revised = true
        return request
    }
}

enum SpokenCommand: Equatable, Sendable {
    case newChat
    case stopListening
}

enum VoiceVerdict: Equatable {
    case listening
    case send(String)
    case discard
}

enum VoiceCommand {
    static let joiningMarks = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.;:-–—"))
    static let leadingMarks = joiningMarks.union(CharacterSet(charactersIn: "!?"))

    static func verdict(for transcript: String, signals: VoiceSignals) -> VoiceVerdict {
        let spoken = SignalPhrase.words(in: transcript)
        if signals.cancel.trailingMatch(in: spoken) != nil { return .discard }
        guard let start = signals.stop.trailingMatch(in: spoken) else { return .listening }
        return .send(beforeSignal(String(transcript[..<spoken[start].range.lowerBound])))
    }

    static func command(in request: String, signals: VoiceSignals) -> SpokenCommand? {
        let spoken = SignalPhrase.words(in: request)
        if signals.newChat.contains(where: { $0.matchesWhole(spoken) }) { return .newChat }
        if signals.listenOff.contains(where: { $0.matchesWhole(spoken) }) { return .stopListening }
        return nil
    }

    static func heardWake(in transcript: String, wake: SignalPhrase) -> HeardWake? {
        let spoken = SignalPhrase.words(in: transcript)
        guard let found = wake.lastMatch(in: spoken) else { return nil }
        return HeardWake(anchor: found.upperBound,
                         request: request(after: found.upperBound, in: transcript, spoken: spoken))
    }

    static func request(in transcript: String, from anchor: Int) -> String? {
        let spoken = SignalPhrase.words(in: transcript)
        guard anchor > 0, anchor <= spoken.count else { return nil }
        return request(after: anchor, in: transcript, spoken: spoken)
    }

    private static func request(after anchor: Int, in transcript: String, spoken: [SpokenWord]) -> String {
        afterSignal(String(transcript[spoken[anchor - 1].range.upperBound...]))
    }

    static func beforeSignal(_ text: String) -> String {
        var kept = text.trimmed
        while let last = kept.unicodeScalars.last, joiningMarks.contains(last) { kept.unicodeScalars.removeLast() }
        return kept
    }

    static func afterSignal(_ text: String) -> String {
        var kept = text.trimmed
        while let first = kept.unicodeScalars.first, leadingMarks.contains(first) { kept.unicodeScalars.removeFirst() }
        return kept.trimmed
    }
}

enum TimingVerdict: Equatable {
    case keep
    case finish
    case nothingSaid
}

struct VoiceTiming: Equatable, Sendable {
    static let standard = VoiceTiming(silence: 4, nothingSaid: 8, maximum: 180)

    var silence: TimeInterval
    var nothingSaid: TimeInterval
    var maximum: TimeInterval

    static func conversation(silence: TimeInterval) -> VoiceTiming {
        VoiceTiming(silence: silence, nothingSaid: 86_400, maximum: 86_400)
    }

    func verdict(startedAt: Date, lastChange: Date?, hasText: Bool, now: Date) -> TimingVerdict {
        let running = now.timeIntervalSince(startedAt)
        if running >= maximum { return hasText ? .finish : .nothingSaid }
        guard hasText else { return running >= nothingSaid ? .nothingSaid : .keep }
        guard let lastChange else { return .keep }
        return now.timeIntervalSince(lastChange) >= silence ? .finish : .keep
    }

    func remaining(startedAt: Date, now: Date) -> Int {
        max(0, Int(ceil(maximum - now.timeIntervalSince(startedAt))))
    }
}
