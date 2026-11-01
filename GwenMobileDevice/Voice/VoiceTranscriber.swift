@testable import GwenMobileFeatureCore
import GwenMobileKit
import AVFoundation
import Foundation

@MainActor
enum VoiceMicrophonePort {
    nonisolated(unsafe) static var allowed: @MainActor () -> Bool = { true }
    nonisolated(unsafe) static var request: @MainActor (@escaping @MainActor (Bool) -> Void) -> Void = { done in
        done(true)
    }
}

@MainActor
final class VoiceTranscriber: ObservableObject {
    enum State { case idle, processing, waiting, recording }

    static let tick = Duration.milliseconds(250)

    @Published var state: State = .idle
    @Published var lastError: L.FriendlyError?
    @Published var remaining: Int?
    @Published private(set) var liveText = ""
    @Published private(set) var wakeWordTriggered = false

    var signals = VoiceSignals.none
    var timing = VoiceTiming.standard

    var onWakeWord: (@MainActor () -> String?)?

    private let makeSource: @MainActor () -> any LiveTranscribing
    private let microphoneAllowed: @MainActor () -> Bool
    private let sentCue: any SoundCueing
    private var source: (any LiveTranscribing)?
    private var onText: (@MainActor (String) -> Void)?
    private var onSpeech: (@MainActor () -> Void)?
    private var onCancel: (@MainActor () -> Void)?
    private var onRejected: (@MainActor () -> Void)?
    private let speakerGate: (any SpeakerGating)?
    private var capture = ""
    private var lastHeard = ""
    private var startedAt = Date()
    private var lastChange: Date?
    private var ticker: Task<Void, Never>?
    private var settling = false
    private var waitsForWake = false
    private var conversation = false
    private var cancelOnly = false
    private var announcedSpeech = false
    private var cancelRequested = false
    private var pendingSpeech = false
    private var pendingCancel = false
    private var wakeGreeting: SignalPhrase?
    private var anchor = WakeAnchor()
    private var epoch = 0

    private struct Session {
        var waitingForWake: Bool
        var conversation = false
        var cancelOnly = false
        var onText: @MainActor (String) -> Void
        var onSpeech: (@MainActor () -> Void)?
        var onCancel: (@MainActor () -> Void)?
        var onRejected: (@MainActor () -> Void)?
    }

    init(makeSource: @escaping @MainActor () -> any LiveTranscribing = {
             VoiceSourcePort.preferred({ HeldMicrophone.shared })
         },
         microphoneAllowed: @escaping @MainActor () -> Bool = { VoiceMicrophonePort.allowed() },
         sentCue: any SoundCueing = ChimePlayer(tone: .sent),
         speakerGate: (any SpeakerGating)? = nil) {
        self.makeSource = makeSource
        self.microphoneAllowed = microphoneAllowed
        self.sentCue = sentCue
        self.speakerGate = speakerGate
    }

    var lastSessionListened: Bool { waitsForWake }
    var isConversationSession: Bool { conversation }
    var isCancelSession: Bool { cancelOnly }

    #if DEBUG
    var probeRecorderActive: Bool { source?.isCapturing ?? false }
    var sourceLabel: String { source?.label ?? "-" }
    var heardSoFar: String { lastHeard }
    #endif

    func start(onText: @escaping @MainActor (String) -> Void) {
        begin(Session(waitingForWake: false, onText: onText))
    }

    func listen(onText: @escaping @MainActor (String) -> Void) {
        begin(Session(waitingForWake: true, onText: onText))
    }

    func listenForCancel(onCancel: @escaping @MainActor () -> Void) {
        begin(Session(waitingForWake: false, cancelOnly: true, onText: { _ in }, onCancel: onCancel))
    }

    func converse(onText: @escaping @MainActor (String) -> Void,
                  onSpeech: @escaping @MainActor () -> Void,
                  onCancel: @escaping @MainActor () -> Void,
                  onRejected: (@MainActor () -> Void)? = nil) {
        begin(Session(waitingForWake: false, conversation: true, onText: onText,
                      onSpeech: onSpeech, onCancel: onCancel, onRejected: onRejected))
    }

    func stopAndTranscribe(onText replacement: (@MainActor (String) -> Void)? = nil) {
        guard !cancelOnly else { cancel(); return }
        switch state {
        case .recording:
            if let replacement { onText = replacement }
            requestDelivery()
        case .processing, .waiting:
            cancel()
        case .idle:
            return
        }
    }

    func cancel() {
        guard state != .idle else { return }
        endSession()
        state = .idle
    }

    func restartListening() {
        if cancelOnly {
            guard let cancelAction = onCancel else { cancel(); return }
            flowMark("VOICE neustart grund=engine")
            cancel()
            listenForCancel(onCancel: cancelAction)
            return
        }
        guard state == .waiting, let keep = onText else { return }
        flowMark("VOICE neustart grund=engine")
        cancel()
        listen(onText: keep)
    }

    func restartConversation() {
        guard conversation, let keep = onText, let speech = onSpeech, let cancelAction = onCancel else { return }
        let rejected = onRejected
        flowMark("VOICE neustart grund=engine")
        cancel()
        converse(onText: keep, onSpeech: speech, onCancel: cancelAction, onRejected: rejected)
    }

    private func begin(_ session: Session) {
        guard state == .idle else { return }
        guard microphoneAllowed() else {
            askForMicrophone(session)
            return
        }
        epoch += 1
        let mine = epoch
        let hints = signals.hints
        let source = makeSource()
        let waitingForWake = session.waitingForWake
        let cancelOnly = session.cancelOnly
        self.source = source
        self.onText = session.onText
        self.onSpeech = session.onSpeech
        self.onCancel = session.onCancel
        self.onRejected = session.onRejected
        waitsForWake = waitingForWake
        wakeWordTriggered = false
        wakeGreeting = nil
        self.conversation = session.conversation
        self.cancelOnly = cancelOnly
        if session.conversation {
            speakerGate?.onVerdict = { [weak self] verdict in self?.speakerVerdictChanged(verdict) }
            speakerGate?.beginSession()
        } else {
            speakerGate?.onVerdict = nil
            speakerGate?.endSession()
        }
        announcedSpeech = false
        cancelRequested = false
        pendingSpeech = false
        pendingCancel = false
        capture = ""
        liveText = ""
        lastChange = nil
        state = .processing
        Task { [weak self] in
            do {
                try await source.start(locale: L.lang.locale, hints: hints,
                                       onText: { [weak self] text in self?.heard(text, epoch: mine) },
                                       onFailure: { [weak self] message in self?.failed(message, epoch: mine) })
                guard let self, self.epoch == mine else {
                    source.stop()
                    return
                }
                self.startedAt = Date()
                self.state = waitingForWake ? .waiting : .recording
                self.startTicker(epoch: mine)
                flowMark("VOICE läuft quelle=\(source.label) weckwort=\(waitingForWake) abbruch=\(cancelOnly)")
            } catch {
                self?.failed(error.localizedDescription, epoch: mine)
            }
        }
    }

    private func askForMicrophone(_ session: Session) {
        VoiceMicrophonePort.request { granted in
            Task { @MainActor in
                if granted {
                    self.begin(session)
                } else {
                    self.lastError = L.FriendlyError(message: L.t("mic_denied"), detail: "", openSettings: false)
                }
            }
        }
    }

    private func heard(_ text: String, epoch mine: Int) {
        guard mine == epoch else { return }
        let wasCancelOnly = cancelOnly
        lastHeard = text
        switch state {
        case .waiting:
            guard let request = anchor.request(in: text, wake: signals.wake) else { return }
            flowMark("VOICE weckwort erkannt")
            wakeWordTriggered = true
            let greeting = onWakeWord?()
            wakeGreeting = greeting.map(SignalPhrase.init)
            state = .recording
            startedAt = Date()
            take(strippingWakeGreeting(request))
        case .recording:
            if waitsForWake {
                guard let request = requestAfterWake(in: text) else { return }
                take(request)
            } else {
                take(text)
            }
        case .idle, .processing:
            return
        }
        guard !conversation, !wasCancelOnly else { return }
        switch VoiceCommand.verdict(for: capture, signals: signals) {
        case .listening:
            return
        case .send(let words):
            flowMark("VOICE stoppwort zeichen=\(words.count)")
            requestDelivery(announced: true)
        case .discard:
            flowMark("VOICE abbruchwort")
            cancel()
        }
    }

    private func requestAfterWake(in text: String) -> String? {
        let wasRevised = anchor.revised
        let request = anchor.request(in: text, wake: signals.wake)
        if anchor.revised, !wasRevised {
            flowMark("VOICE weckwort umgedeutet stelle=\(anchor.position)")
        }
        return request.map(strippingWakeGreeting)
    }

    private func strippingWakeGreeting(_ text: String) -> String {
        guard let wakeGreeting else { return text }
        let spoken = SignalPhrase.words(in: text)
        guard spoken.count >= wakeGreeting.words.count else { return text }
        for index in wakeGreeting.words.indices {
            guard SignalPhrase.similar(wakeGreeting.words[index], spoken[index].folded) else { return text }
        }
        let end = spoken[wakeGreeting.words.count - 1].range.upperBound
        return VoiceCommand.afterSignal(String(text[end...]))
    }

    static func confirmsConversationSpeech(_ text: String) -> Bool {
        let words = SignalPhrase.words(in: text)
        guard !words.isEmpty else { return false }
        if words.count >= 2 { return true }
        return words.contains { $0.folded.count >= 5 }
    }

    private func take(_ text: String) {
        if text != capture {
            capture = text
            lastChange = Date()
        }
        if cancelOnly {
            liveText = ""
            guard !cancelRequested, heardCancelWord else { return }
            cancelRequested = true
            let callback = onCancel
            callback?()
            cancel()
            return
        }
        liveText = capture
        if conversation, !cancelRequested, heardCancelWord {
            cancelRequested = true
            pendingCancel = true
            resolveSpeakerActions()
            return
        }
        guard conversation, !cancelRequested, !announcedSpeech,
              Self.confirmsConversationSpeech(capture) else { return }
        pendingSpeech = true
        resolveSpeakerActions()
    }

    private var heardCancelWord: Bool {
        signals.cancel.lastMatch(in: SignalPhrase.words(in: capture)) != nil
    }

    private func resolveSpeakerActions() {
        guard let gate = speakerGate, gate.isActive else {
            firePendingActions()
            return
        }
        guard gate.verdict == .allowed else { return }
        firePendingActions()
    }

    private func firePendingActions() {
        if pendingCancel {
            pendingCancel = false
            announcedSpeech = true
            onCancel?()
            return
        }
        if pendingSpeech {
            pendingSpeech = false
            announcedSpeech = true
            onSpeech?()
        }
    }

    private func speakerVerdictChanged(_ verdict: SpeakerVerdict) {
        guard verdict == .allowed else { return }
        resolveSpeakerActions()
    }

    private func startTicker(epoch mine: Int) {
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tick)
                guard let self, self.epoch == mine else { return }
                self.checkTime()
            }
        }
    }

    private func checkTime() {
        guard state == .recording else {
            if remaining != nil { remaining = nil }
            return
        }
        if cancelOnly {
            if remaining != nil { remaining = nil }
            return
        }
        if conversation {
            if remaining != nil { remaining = nil }
            guard !capture.isEmpty, let lastChange else { return }
            guard Date().timeIntervalSince(lastChange) >= timing.silence else { return }
            guard announcedSpeech || pendingSpeech || cancelRequested else {
                flowMark("VOICE verworfen text=\(TextLine.oneLine(capture, limit: 80))")
                capture = ""
                liveText = ""
                pendingSpeech = false
                pendingCancel = false
                cancelRequested = false
                return
            }
            flowMark("VOICE stille zeichen=\(capture.count)")
            requestDelivery(announced: false)
            return
        }
        let now = Date()
        let left = timing.remaining(startedAt: startedAt, now: now)
        if remaining != left { remaining = left }
        switch timing.verdict(startedAt: startedAt, lastChange: lastChange, hasText: !capture.isEmpty, now: now) {
        case .keep:
            return
        case .finish:
            flowMark("VOICE stille zeichen=\(capture.count)")
            requestDelivery(announced: true)
        case .nothingSaid:
            flowMark("VOICE nichts gesagt weckwort=\(waitsForWake)")
            guard !waitsForWake else {
                cancel()
                return
            }
            fail(with: L.FriendlyError(message: L.t("asr_empty"), detail: "", openSettings: false))
        }
    }

    private func requestDelivery(announced: Bool = false) {
        let mine = epoch
        guard let finalizing = source as? any FinalizingTranscribing else {
            if conversation, speakerGate?.isActive == true {
                Task { @MainActor [weak self] in
                    await self?.deliverWithSpeakerCheck(announced: announced, epoch: mine)
                }
            } else {
                deliverByVerdict(announced: announced)
            }
            return
        }
        guard !settling else { return }
        settling = true
        Task { @MainActor [weak self] in
            let settled = await finalizing.settle()
            guard let self, self.epoch == mine else { return }
            self.settling = false
            if let settled, !settled.isEmpty {
                self.lastHeard = settled
                if self.waitsForWake {
                    if let request = self.anchor.request(in: settled, wake: self.signals.wake) {
                        self.take(self.strippingWakeGreeting(request))
                    }
                } else {
                    self.take(settled)
                }
            }
            await self.deliverWithSpeakerCheck(announced: announced, epoch: mine)
        }
    }

    private func deliverWithSpeakerCheck(announced: Bool, epoch mine: Int) async {
        guard conversation, let gate = speakerGate, gate.isActive else {
            deliverByVerdict(announced: announced)
            return
        }
        let verdict = await gate.finalVerdict()
        guard epoch == mine else { return }
        guard verdict == .allowed else {
            rejectConversationTurn()
            return
        }
        resolveSpeakerActions()
        guard !cancelRequested else { return }
        deliverByVerdict(announced: announced)
    }

    private func rejectConversationTurn() {
        let callback = onRejected
        flowMark("GESPRAECH stimme abgelehnt")
        cancel()
        callback?()
    }

    private func deliverByVerdict(announced: Bool) {
        if conversation {
            guard !cancelRequested else { return }
            deliver(capture, announced: false)
            return
        }
        switch VoiceCommand.verdict(for: capture, signals: signals) {
        case .send(let words):
            deliver(words, announced: announced)
        case .discard:
            cancel()
        case .listening:
            deliver(capture, announced: announced)
        }
    }

    private func deliver(_ spoken: String, announced: Bool = false) {
        let text = spoken.trimmed
        let callback = onText
        let wasConversation = conversation
        endSession()
        state = .idle
        guard !text.isEmpty else {
            if !wasConversation, !waitsForWake {
                lastError = L.FriendlyError(message: L.t("asr_empty"), detail: "", openSettings: false)
            }
            return
        }
        if announced, waitsForWake { sentCue.play() }
        callback?(text)
    }

    private func failed(_ message: String, epoch mine: Int) {
        guard mine == epoch else { return }
        fail(with: L.friendlyError(message))
    }

    private func fail(with error: L.FriendlyError) {
        endSession()
        state = .idle
        lastError = error
    }

    private func endSession() {
        if source != nil {
            flowMarkPersonal("VOICE ende zustand=\(state) zuletzt=\(TextLine.oneLine(lastHeard, limit: 160))")
        }
        settling = false
        lastHeard = ""
        anchor = WakeAnchor()
        epoch += 1
        ticker?.cancel()
        ticker = nil
        source?.stop()
        source = nil
        onText = nil
        onSpeech = nil
        onCancel = nil
        onRejected = nil
        speakerGate?.onVerdict = nil
        speakerGate?.endSession()
        conversation = false
        cancelOnly = false
        wakeWordTriggered = false
        wakeGreeting = nil
        announcedSpeech = false
        cancelRequested = false
        pendingSpeech = false
        pendingCancel = false
        remaining = nil
        capture = ""
        liveText = ""
        lastChange = nil
    }
}
