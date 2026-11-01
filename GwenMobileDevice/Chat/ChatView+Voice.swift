@testable import GwenMobileFeatureCore
@testable import GwenMobileAdapters
import GwenMobileKit
import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

extension ChatView {
    @MainActor func takeListenRequest(from source: String) {
        let token = listenToken?.wrappedValue ?? 0
        guard token > handledListen else { return }
        handledListen = token
        flowMark("LISTEN uebernommen quelle=\(source) token=\(token)")
        startListeningFromShortcut()
    }

    @MainActor func startListeningFromShortcut() {
        if voice.state == .waiting { voice.cancel() }
        guard !settings.voice.conversationMode else { return }
        guard voice.state == .idle, !isStreaming, !busy.isBusy else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard settings.isConfigured, voice.state == .idle, !isStreaming, !busy.isBusy else { return }
            startRecording(from: "kurzbefehl")
        }
    }

    @MainActor func startRecording(from source: String) {
        flowMark("VOICE start quelle=\(source) anhaenge=\(pendingImages.count) zeichen=\(input.count) "
                 + "fokus=\(inputFocused) sprache=\(AVAudioApplication.shared.recordPermission.rawValue)")
        inputFocused = false
        voice.signals = settings.voiceSignals
        voice.timing = settings.voiceTiming
        voice.start { text in
            self.voiceDidTranscribe(text)
        }
    }

    var listenGate: ListenGate {
        let conversation = settings.voice.conversationMode
        return ListenGate(enabled: settings.voice.listenMode || conversation,
                          configured: settings.isConfigured, foreground: scenePhase == .active,
                          microphoneLive: microphone.isLive,
                          working: isBusy || isStreaming || busy.isBusy || chainRun.isRunning,
                          speaking: speech.isSpeaking,
                          sheetOpen: showSettings || showHistory || showBriefingOpen
                              || imagePreview != nil || calendarEvent != nil,
                          conversation: conversation)
    }

    var voiceWorking: Bool {
        runTask != nil || isBusy || isStreaming || busy.isBusy || chainRun.isRunning
    }

    private var speechModeEnabled: Bool {
        settings.voice.conversationMode || settings.voice.listenMode
    }

    var listenGlowPhase: ListenGlowPhase {
        let gate = listenGate
        return ListenGlowPolicy.phase(foreground: gate.foreground,
                                      sheetOpen: gate.sheetOpen || showHelp,
                                      wakeWord: voice.wakeWordTriggered,
                                      voice: voice.state)
    }

    var listenLivePlan: ListenLivePlan {
        let gate = listenGate
        return ListenLivePlan.plan(foreground: gate.foreground,
                                   sheetOpen: gate.sheetOpen || showHelp,
                                   listenMode: settings.voice.listenMode,
                                   conversationMode: settings.voice.conversationMode,
                                   microphoneLive: gate.microphoneLive,
                                   voice: voice.state,
                                   working: voiceWorking)
    }

    @MainActor func syncListenPresence() {
        ListenLiveActivityBridge.apply(listenLivePlan)
    }

    @MainActor func installWakeGreeting() {
        let speech = wakeSpeech
        let settings = self.settings
        voice.onWakeWord = { [weak speech] in
            guard let speech else { return nil }
            let greeting = WakeGreeting.random()
            speech.speak(text: greeting, voiceIdentifier: settings.voice.outputVoice)
            return greeting
        }
    }

    @MainActor func followListenGate(_ gate: ListenGate) {
        #if DEBUG
        UIApplication.shared.isIdleTimerDisabled = gate.keepsScreenAwake || testRunning
        #else
        UIApplication.shared.isIdleTimerDisabled = gate.keepsScreenAwake
        #endif
        followMicrophoneHold(gate)
        if gate.conversation {
            guard !voiceCancelFeedback else { return }
            if voice.isCancelSession { voice.cancel(); return }
            guard gate.mayListen else {
                if voice.state == .waiting || voice.isConversationSession || voice.isCancelSession {
                    voice.cancel()
                }
                return
            }
            if voice.state == .waiting { voice.cancel(); return }
            if voice.state == .idle { startConversationListening() }
            return
        }
        if voice.isConversationSession { voice.cancel(); return }
        if voice.isCancelSession {
            if gate.mayCancel { return }
            voice.cancel()
        }
        guard !voiceCancelFeedback else { return }
        guard gate.mayListen else {
            if gate.mayCancel {
                if voice.state != .idle { voice.cancel() }
                guard voice.state == .idle else { return }
                startListening(forCancel: true)
                return
            }
            if voice.state == .waiting { voice.cancel() }
            return
        }
        guard voice.state == .idle else { return }
        startListening()
    }

    @MainActor func startListening(forCancel: Bool = false) {
        guard settings.voice.listenMode, settings.isConfigured, !settings.voice.conversationMode,
              voice.state == .idle,
              forCancel ? listenGate.mayCancel : listenGate.mayListen else { return }
        let microphone = self.microphone
        Task { @MainActor in
            do {
                try await microphone.setVoiceProcessing(true)
            } catch {
                settings.voice.listenMode = false
                voice.cancel()
                Task { try? await microphone.setVoiceProcessing(false) }
                queueAlert(L.FriendlyError(message: L.t("listen_echo_failed"),
                                           detail: error.localizedDescription, openSettings: false))
                syncListenPresence()
                return
            }
            guard settings.voice.listenMode, settings.isConfigured,
                  !settings.voice.conversationMode else {
                try? await microphone.setVoiceProcessing(false)
                return
            }
            guard voice.state == .idle,
                  forCancel ? listenGate.mayCancel : listenGate.mayListen else { return }
            voice.signals = settings.voiceSignals
            if forCancel {
                voice.listenForCancel { self.handleVoiceCancel() }
                return
            }
            voice.timing = settings.voiceTiming
            voice.listen { text in
                self.voiceDidTranscribe(text)
            }
        }
    }

    @MainActor func startConversationListening() {
        guard settings.voice.conversationMode, settings.isConfigured else { return }
        if let issue = speakerGateIssue {
            settings.voice.conversationMode = false
            listenNotice.show(L.t(issue))
            return
        }
        guard voice.state == .idle, listenGate.mayListen else { return }
        let microphone = self.microphone
        Task { @MainActor in
            do {
                try await microphone.setVoiceProcessing(true)
            } catch {
                disableConversation(error)
                return
            }
            guard settings.voice.conversationMode, listenGate.mayListen, voice.state == .idle else { return }
            if settings.voice.onlyMyVoice {
                let usable = await SpeakerEmbedder.shared.ensureUsable()
                guard settings.voice.conversationMode else { return }
                guard usable else {
                    settings.voice.conversationMode = false
                    voice.cancel()
                    listenNotice.show(L.t("speaker_model_unavailable"))
                    return
                }
            }
            voice.signals = settings.voiceSignals
            voice.timing = .conversation(silence: TimeInterval(settings.voice.dictationSilenceSeconds))
            voice.converse(onText: { text in
                self.voiceDidTranscribe(text)
            }, onSpeech: {
                self.userStartedSpeaking()
            }, onCancel: {
                self.handleVoiceCancel()
            }, onRejected: {
                self.listenNotice.show(L.t("speaker_ignored"))
            })
        }
    }

    @MainActor private func disableConversation(_ error: Error) {
        flowMark("GESPRAECH echo fehlgeschlagen \(TextLine.oneLine(error.localizedDescription, limit: 80))")
        settings.voice.conversationMode = false
        voice.cancel()
        Task { try? await microphone.setVoiceProcessing(false) }
        queueAlert(L.FriendlyError(message: L.t("conversation_echo_failed"),
                                   detail: error.localizedDescription, openSettings: false))
    }

    @MainActor func userStartedSpeaking() {
        guard settings.voice.conversationMode else { return }
        speechInterrupted = true
        speech.stop()
        guard runTask != nil || isBusy || isStreaming || busy.isBusy || chainRun.isRunning else { return }
        flowMark("GESPRAECH sprache unterbricht laufend=\(runTask != nil) busy=\(isBusy) "
                 + "stream=\(isStreaming) kette=\(chainRun.isRunning)")
        cancelLiveWork()
    }

    @MainActor func settleInterruptedRun(stopSpeech: Bool = true) async {
        guard let running = runTask else { return }
        let generation = runGeneration
        cancelLiveWork()
        await running.value
        guard generation == runGeneration else { return }
        if stopSpeech { speech.stop() }
        runTask = nil
    }

    @MainActor func handleVoiceCancel() {
        guard speechModeEnabled, !voiceCancelFeedback else { return }
        flowMark("VOICE abbruchwort laufend=\(runTask != nil) busy=\(isBusy) "
                 + "stream=\(isStreaming) kette=\(chainRun.isRunning) spricht=\(speech.isSpeaking)")
        voiceCancelFeedback = true
        stopRunningAnswer()
        Task { @MainActor in voice.cancel() }
        speech.speak(text: L.t("conversation_stopped"), voiceIdentifier: settings.voice.outputVoice)
        Task { @MainActor in
            await settleInterruptedRun(stopSpeech: false)
            for _ in 0..<100 {
                guard speech.isSpeaking else { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            try? await Task.sleep(for: .milliseconds(300))
            guard speechModeEnabled else {
                voiceCancelFeedback = false
                return
            }
            voiceCancelFeedback = false
            followListenGate(listenGate)
        }
    }

    @MainActor private func conversationDidHear(_ text: String) {
        let spoken = text.trimmed
        guard !spoken.isEmpty else { return }
        speech.stop()
        startConversationListening()
        Task { @MainActor in
            await settleInterruptedRun()
            guard settings.voice.conversationMode else { return }
            let draft = input.trimmed
            input = draft.isEmpty ? spoken : "\(draft) \(spoken)"
            startSend()
        }
    }

    @MainActor func followMicrophoneHold(_ gate: ListenGate) {
        guard gate.holdsMicrophone != microphone.isHeld else { return }
        guard gate.holdsMicrophone else {
            microphone.release()
            return
        }
        microphone.hold(onLoss: { self.microphoneLost() })
        listenNotices.prepare()
    }

    @MainActor func microphoneLost() {
        let away = UIApplication.shared.applicationState != .active
        flowMark("ZUHOEREN mikrofon verloren hintergrund=\(away) zustand=\(voice.state)")
        voice.cancel()
        if away { listenNotices.listeningStopped() }
        syncListenPresence()
    }

    @MainActor func refreshVoiceAfterEngineChange() {
        if settings.voice.conversationMode {
            voice.restartConversation()
            return
        }
        guard settings.voice.listenMode else { return }
        voice.restartListening()
    }

    @MainActor func toggleListenMode() {
        switch ListenSwitch.tap(isOn: settings.voice.listenMode, configured: settings.isConfigured) {
        case .openSettings:
            showSettings = true
        case .turned(let on):
            settings.voice.conversationMode = false
            settings.voice.listenMode = on
            if on { voice.cancel() }
            if !on { Task { try? await microphone.setVoiceProcessing(false) } }
            listenNotice.show(L.t(ListenSwitch.noticeKey(on: on)))
            flowMark("ZUHOEREN knopf an=\(on)")
            syncListenPresence()
        }
    }

    var speakerGateIssue: String? {
        guard settings.voice.onlyMyVoice else { return nil }
        guard SpeakerProfileStore.shared.load() != nil else { return "speaker_profile_missing" }
        guard SpeakerEmbedder.shared.hasModel, SpeakerEmbedder.shared.cachedUsability != false else {
            return "speaker_model_unavailable"
        }
        return nil
    }

    @MainActor func toggleConversationMode() {
        guard settings.isConfigured else { showSettings = true; return }
        let on = !settings.voice.conversationMode
        if on, let issue = speakerGateIssue {
            listenNotice.show(L.t(issue))
            showSettings = true
            return
        }
        settings.voice.conversationMode = on
        if on {
            settings.voice.listenMode = false
        }
        voice.cancel()
        if !on { Task { try? await microphone.setVoiceProcessing(false) } }
        listenNotice.show(L.t(on ? "conversation_notice_on" : "conversation_notice_off"))
        flowMark("GESPRAECH knopf an=\(on)")
        syncListenPresence()
    }

    var voiceBusy: Bool { voice.state == .recording || voice.state == .processing }

    @MainActor func abortVoice() {
        flowMark("VOICE abbruch zustand=\(voice.state) anhaenge=\(pendingImages.count) zeichen=\(input.count)")
        voice.cancel()
    }

    @MainActor func voiceDidTranscribe(_ text: String) {
        if settings.voice.conversationMode {
            conversationDidHear(text)
            return
        }
        if voice.lastSessionListened, let command = VoiceCommand.command(in: text, signals: settings.voiceSignals) {
            perform(command)
            return
        }
        let draft = input.trimmed
        input = draft.isEmpty ? text : "\(draft) \(text)"
        startSend()
    }

    @MainActor func perform(_ command: SpokenCommand) {
        switch command {
        case .newChat:
            flowMark("VOICE befehl neuer_chat leer_vorher=\(store.current?.messages.isEmpty ?? true)")
            store.startFreshConversation()
        case .stopListening:
            let away = UIApplication.shared.applicationState != .active
            flowMark("VOICE befehl zuhoeren_aus hintergrund=\(away)")
            settings.voice.listenMode = false
            listenNotice.show(L.t(ListenSwitch.noticeKey(on: false)))
            if away { listenNotices.answered(L.t("listen_off_by_voice")) }
            Task { try? await microphone.setVoiceProcessing(false) }
            syncListenPresence()
        }
    }

    func toggleVoice() {
        guard settings.isConfigured else { showSettings = true; return }
        switch voice.state {
        case .idle:
            startRecording(from: "taste")
        case .waiting:
            voice.cancel()
            startRecording(from: "taste")
        case .recording:
            voice.stopAndTranscribe()
        case .processing:
            break
        }
    }

    @MainActor func speakWeather(message: UUID) {
        guard let text = store.current?.messages.first(where: { $0.id == message })?.text,
              !text.isEmpty else { return }
        speech.speak(text: text, voiceIdentifier: settings.voice.outputVoice)
    }

    @MainActor func speakLastAnswer(convID: UUID, started: Date, slot: AnswerSlot? = nil) {
        let spoken = store.current?.messages.last { $0.role == .assistant && !$0.text.isEmpty }?.text ?? ""
        flowMarkPersonal("VORLESEN letzte_antwort zeichen=\(spoken.count)")
        let text = spoken.isEmpty ? L.t("read_answer_empty") : L.t("read_answer_started")
        let model = settings.chatModel
        finishAnswer(text, model: model, convID: convID, started: started, slot: slot, announce: false)
        guard !spoken.isEmpty else { return }
        speech.speak(text: spoken, voiceIdentifier: settings.voice.outputVoice)
    }

    @MainActor func runReadAloudFlow(_ request: ReadAloudRequest, convID: UUID, started: Date,
                                             slot: AnswerSlot? = nil) async {
        settings.voice.speakAnswers = request.enabled
        flowMarkPersonal("VORLESEN an=\(request.enabled)")
        let text = L.t(request.enabled ? "read_aloud_on" : "read_aloud_off")
        let model = settings.chatModel
        finishAnswer(text, model: model, convID: convID, started: started, slot: slot)
    }

    var speaksWhileAnswering: Bool {
        !speechInterrupted && (settings.voice.speakAnswers || settings.voice.conversationMode)
    }

    func announceAnswer(_ text: String) {
        let plan = AnswerAnnouncement.plan(readAloud: settings.voice.speakAnswers || settings.voice.conversationMode,
                                           foreground: UIApplication.shared.applicationState == .active,
                                           listening: settings.voice.listenMode || settings.voice.conversationMode)
        guard !speechInterrupted else { return }
        let streamed = speech.takeStreamed()
        if plan.notifies { listenNotices.answered(text) }
        guard plan.speaks, !streamed else { return }
        speech.speak(text: text, voiceIdentifier: settings.voice.outputVoice)
    }

}
