@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import UIKit

extension DebugFeatureProbe {
    @MainActor
    private struct ConversationBaseline {
        let conversation: Bool
        let listen: Bool
        let speak: Bool

        init(_ view: ChatView) {
            let voice = view.settings.voice
            conversation = voice.conversationMode
            listen = voice.listenMode
            speak = voice.speakAnswers
            view.settings.voice.listenMode = false
            view.settings.voice.speakAnswers = true
            view.settings.voice.conversationMode = false
            view.probeAbortVoice()
        }

        func restore(_ settings: AppSettings) {
            settings.voice.conversationMode = conversation
            settings.voice.listenMode = listen
            settings.voice.speakAnswers = speak
        }
    }

    @MainActor
    private static func conversationReady(_ view: ChatView,
                                          preparing: @MainActor () -> Void = {}) async -> Bool {
        try? await Task.sleep(for: .milliseconds(250))
        preparing()
        view.toggleConversationMode()
        return await ProbeWait.until(20) {
            view.probeVoiceState == .recording && HeldMicrophone.shared.isVoiceProcessing
        }
    }

    @MainActor
    private static func pauseConversation(_ view: ChatView) {
        view.settings.voice.conversationMode = false
        view.probeAbortVoice()
        view.speech.stop()
    }

    static func micLoop(_: ChatView) async {
        let report = SweepReport(file: "mic_loop.txt")
        let heard = TranscriptBox()
        let voice = VoiceTranscriber()
        let speech = SpeechSynthesizer()
        voice.start { text in heard.text = text }
        let live = await ProbeWait.until(10) { voice.state != .idle }
        report.add("MIKLOOP_AUFNAHME", "zustand=\(voice.state) live=\(live)")
        speech.speak(text: "Die Kernfusion verbindet leichte Atomkerne.")
        let started = ContinuousClock.now
        _ = await ProbeWait.until(40) { !speech.isSpeaking }
        report.add("MIKLOOP_WAEHREND", "aufnahme=\(voice.state) spricht=\(speech.isSpeaking) "
                   + "warte_s=\(Int(msOf(started.duration(to: .now)) / 1000))")
        voice.stopAndTranscribe()
        let waited = await waitForIdle(voice)
        report.add("MIKLOOP_ERGEBNIS", "zustand=\(voice.state) sekunden=\(waited) "
                   + "fehler=\(voice.lastError.map { $0.message } ?? "keine") "
                   + "text=\(heard.text.map { TextLine.oneLine($0, limit: 160) } ?? "keiner")")
        flowLog.info("MIKLOOP fertig")
    }

    static func modeFlip(_ view: ChatView) async {
        let report = SweepReport(file: "mode_flip.txt")
        report.add("START", "bereit=\(view.settings.isConfigured) zuhoeren=\(view.settings.voice.listenMode) "
                   + "gespraech=\(view.settings.voice.conversationMode)")
        for step in 1...8 {
            view.probeToggleListenMode()
            report.add("ZUHOEREN", "schritt=\(step) an=\(view.settings.voice.listenMode) "
                       + "zustand=\(view.probeVoiceState) echschutz=\(HeldMicrophone.shared.isVoiceProcessing)")
            try? await Task.sleep(for: .milliseconds(1200))
            view.toggleConversationMode()
            report.add("GESPRAECH", "schritt=\(step) an=\(view.settings.voice.conversationMode) "
                       + "zustand=\(view.probeVoiceState) echschutz=\(HeldMicrophone.shared.isVoiceProcessing)")
            try? await Task.sleep(for: .milliseconds(1200))
        }
        view.probeAbortVoice()
        view.settings.voice.listenMode = false
        view.settings.voice.conversationMode = false
        report.add("ENDE", "zustand=\(view.probeVoiceState)")
    }

    static func voiceAbort(_ view: ChatView) async {
        let report = SweepReport(file: "voice_abort.txt")
        guard let shot = await view.flowTestPicture() else {
            report.add("SPRACHABBRUCH", "kein Referenzbild")
            return
        }
        let store = view.store
        store.newConversation()
        view.pendingImages = [PendingPicture(image: shot, file: nil)]
        let before = store.current?.messages.count ?? -1

        let first = TranscriptBox()
        let recording = VoiceTranscriber()
        recording.start { first.text = $0 }
        try? await Task.sleep(for: .seconds(3))
        report.add("WAEHREND_AUFNAHME", "zustand=\(recording.state) anhang=\(view.pendingImages.count) "
                   + "nachrichten=\(store.current?.messages.count ?? -1) vorher=\(before)")
        recording.cancel()
        _ = await ProbeWait.until(5) { recording.state == .idle }
        report.add("NACH_ABBRUCH", "zustand=\(recording.state) text=\(first.text ?? "keiner") "
                   + "fehler=\(recording.lastError.map { $0.message } ?? "keine") "
                   + "nachrichten=\(store.current?.messages.count ?? -1) anhang=\(view.pendingImages.count)")

        let second = TranscriptBox()
        let running = VoiceTranscriber()
        running.start { second.text = $0 }
        try? await Task.sleep(for: .seconds(2))
        running.stopAndTranscribe()
        report.add("UEBERGABE_START", "zustand=\(running.state)")
        running.cancel()
        _ = await ProbeWait.until(5) { running.state == .idle }
        report.add("UEBERGABE_ABBRUCH", "zustand=\(running.state) text=\(second.text ?? "keiner") "
                   + "nachrichten=\(store.current?.messages.count ?? -1)")
        _ = await ProbeWait.until(10) { second.text != nil || running.state == .idle }
        report.add("SPAETER", "text=\(second.text ?? "keiner") zustand=\(running.state) "
                   + "nachrichten=\(store.current?.messages.count ?? -1)")
        view.pendingImages = []
        flowLog.info("SPRACHABBRUCH fertig")
    }

    static func waitForIdle(_ voice: VoiceTranscriber, limit: Int = 40) async -> Int {
        let started = ContinuousClock.now
        _ = await ProbeWait.until(limit) { voice.state == .idle }
        return Int(msOf(started.duration(to: .now)) / 1000)
    }

    static func micRecord(_: ChatView) async {
        let report = SweepReport(file: "mic_rec.txt")
        let heard = TranscriptBox()
        let voice = VoiceTranscriber()
        voice.start { text in heard.text = text }
        report.add("MIKRO_START", "zustand=\(voice.state) restlich=\(String(describing: voice.remaining))")
        try? await Task.sleep(for: .seconds(4))
        report.add("MIKRO_NACH_VIER", "zustand=\(voice.state) restlich=\(String(describing: voice.remaining))")
        voice.stopAndTranscribe()
        report.add("MIKRO_STOPP", "zustand=\(voice.state)")
        let waited = await waitForIdle(voice)
        report.add("MIKRO_ENDE", "zustand=\(voice.state) sekunden=\(waited) "
                   + "fehler=\(voice.lastError.map { $0.message } ?? "keine") "
                   + "text=\(heard.text.map { TextLine.oneLine($0, limit: 160) } ?? "keiner")")
        flowLog.info("MIKRO fertig")
    }

    static func conversationEcho(_ view: ChatView) async {
        let report = SweepReport(file: "conversation_echo.txt")
        let microphone = view.microphone
        do {
            try await microphone.setVoiceProcessing(true)
        } catch {
            report.addFailure("ECHOSCHUTZ", error)
            return
        }
        let voice = VoiceTranscriber()
        voice.timing = .conversation(silence: 2)
        let heard = TranscriptBox()
        var interruptions = 0
        voice.converse(onText: { heard.text = $0 }, onSpeech: { interruptions += 1 }, onCancel: {})
        _ = await ProbeWait.until(20) { voice.state == .recording || voice.lastError != nil }
        report.add("GESPRAECH_START", "zustand=\(voice.state) echschutz=\(microphone.isVoiceProcessing) "
                   + "quelle=\(voice.sourceLabel) fehler=\(voice.lastError.map { $0.message } ?? "keiner")")
        guard voice.state == .recording else {
            voice.cancel()
            try? await microphone.setVoiceProcessing(false)
            return
        }
        let speech = SpeechSynthesizer()
        speech.speak(text: "Die Kernfusion verbindet leichte Atomkerne zu schwereren.")
        var live = ""
        var speakingTicks = 0
        var interruptedAt = -1
        let started = ContinuousClock.now
        for tick in 0...80 {
            if !voice.liveText.isEmpty { live = voice.liveText }
            if interruptions > 0, interruptedAt < 0 { interruptedAt = tick }
            if speech.isSpeaking { speakingTicks += 1 }
            if interruptions == 0, !speech.isSpeaking, speakingTicks > 0 { break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        report.add("ECHO_WAEHREND", "gehoert=\(TextLine.oneLine(live, limit: 200)) "
                   + "unterbrechungen=\(interruptions) unterbrechung_bei_s=\(Double(interruptedAt) / 4) "
                   + "spricht_noch=\(speech.isSpeaking) ms=\(msOf(started.duration(to: .now)))")
        voice.cancel()
        speech.stop()
        try? await microphone.setVoiceProcessing(false)
        report.add("GESPRAECH_ENDE", "zustand=\(voice.state) gesendet=\(heard.text.map { TextLine.oneLine($0, limit: 120) } ?? "keiner") "
                   + "echschutz=\(microphone.isVoiceProcessing) fehler=\(voice.lastError.map { $0.message } ?? "keiner")")
        flowLog.info("GESPRAECH fertig")
    }

    static func conversationSilence(_ view: ChatView) async {
        let report = SweepReport(file: "conversation_silence.txt")
        let baseline = ConversationBaseline(view)
        let ready = await conversationReady(view)
        report.add("START", "bereit=\(ready) modus=\(view.settings.voice.conversationMode) "
                   + "zustand=\(view.probeVoiceState) echschutz=\(HeldMicrophone.shared.isVoiceProcessing)")
        var last = ""
        var heard = ""
        var peakMax: Float = 0
        for tick in 0..<200 {
            if !view.voice.liveText.isEmpty, view.voice.liveText != last {
                last = view.voice.liveText
                heard = last
                report.add("GEHOERT", "text=\(TextLine.oneLine(last, limit: 160))")
            }
            peakMax = max(peakMax, HeldMicrophone.shared.currentPeak)
            if tick % 20 == 19 {
                report.add("PEGEL", "s=\(Double(tick + 1) / 10) db=\(AudioLevelMeter.decibels(peakMax))")
                peakMax = 0
            }
            if view.speechInterrupted { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        report.add("STILLE", "gehoert=\(TextLine.oneLine(heard, limit: 200)) "
                   + "unterbrochen=\(view.speechInterrupted) zustand=\(view.probeVoiceState)")
        pauseConversation(view)
        baseline.restore(view.settings)
        flowMark("STILLE_ENDE")
    }

    static func conversationBargeIn(_ view: ChatView) async {
        let report = SweepReport(file: "conversation_barge.txt")
        let baseline = ConversationBaseline(view)
        let ready = await conversationReady(view)
        report.add("START", "bereit=\(ready) modus=\(view.settings.voice.conversationMode) "
                   + "zustand=\(view.probeVoiceState) echschutz=\(HeldMicrophone.shared.isVoiceProcessing) "
                   + "sprache=\(L.lang.rawValue)")
        guard ready else {
            pauseConversation(view)
            baseline.restore(view.settings)
            flowMark("BARGE_ENDE")
            return
        }
        view.speech.stop()
        view.speechInterrupted = false
        let long = "Das ist eine absichtlich lange Antwort, damit genug Zeit bleibt, um mitten hineinzusprechen. "
            + "Die Kernfusion verbindet leichte Atomkerne zu schwereren Kernen und setzt dabei Energie frei. "
            + "Auf der Erde versucht man, diesen Vorgang in großen Anlagen nachzubauen, damit eines Tages Strom "
            + "ohne fossile Brennstoffe entsteht. Bis dahin sind noch viele technische Fragen zu lösen, zum Beispiel "
            + "die Hitze im Inneren des Reaktors, die Stabilität des Plasmas und die Materialien, die den Belastungen "
            + "standhalten. Forscherinnen und Forscher arbeiten deshalb weltweit an besseren Magneten, neuen "
            + "Diagnoseverfahren und sicheren Kühlkreisläufen. Gleichzeitig werden kleinere Experimente gebaut, um "
            + "einzelne Bauteile unabhängig voneinander zu testen. Der Weg zur kommerziellen Nutzung ist lang, aber "
            + "jeder Schritt liefert wichtige Erkenntnisse über die Physik und die Technik der Zukunft."
        flowMark("BARGE_TTS_START zeichen=\(long.count)")
        let start = ContinuousClock.now
        view.speech.speak(text: long, voiceIdentifier: view.settings.voice.outputVoice)
        _ = await ProbeWait.until(5) { view.probeSpeaking }
        var sawSpeech = false
        var lastHeard = ""
        var bargeAt = -1.0
        var liveAtBarge = ""
        var stoppedNaturally = false
        var peakMax: Float = 0
        for tick in 0..<400 {
            let elapsed = Double(msOf(start.duration(to: .now))) / 1000
            if view.probeSpeaking { sawSpeech = true }
            peakMax = max(peakMax, HeldMicrophone.shared.currentPeak)
            if tick % 10 == 9 {
                report.add("PEGEL", "s=\(String(format: "%.1f", elapsed)) db=\(AudioLevelMeter.decibels(peakMax))")
                peakMax = 0
            }
            if !view.voice.liveText.isEmpty, view.voice.liveText != lastHeard {
                lastHeard = view.voice.liveText
                report.add("GEHOERT", "s=\(String(format: "%.1f", elapsed)) "
                           + "text=\(TextLine.oneLine(lastHeard, limit: 160))")
            }
            if view.speechInterrupted || (sawSpeech && !view.probeSpeaking) {
                if view.speechInterrupted {
                    bargeAt = elapsed
                    liveAtBarge = view.voice.liveText
                } else {
                    stoppedNaturally = true
                }
                break
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        let interrupted = bargeAt >= 0
        report.add("ZWISCHENRUF", "erkannt=\(interrupted) bei_s=\(String(format: "%.1f", bargeAt)) "
                   + "gehoert=\(TextLine.oneLine(liveAtBarge, limit: 200)) "
                   + "spricht_noch=\(view.probeSpeaking) unterbrochen=\(view.speechInterrupted) "
                   + "natuerlich_zuende=\(stoppedNaturally) zustand=\(view.probeVoiceState) "
                   + "mikrofon=\(HeldMicrophone.shared.isLive) echschutz=\(HeldMicrophone.shared.isVoiceProcessing)")
        pauseConversation(view)
        try? await Task.sleep(for: .milliseconds(300))
        report.add("ENDE", "modus=\(view.settings.voice.conversationMode) zustand=\(view.probeVoiceState) "
                   + "nachrichten=\(view.store.current?.messages.count ?? -1) "
                   + "alarme=\(view.probeAlerts.map { $0.message }.joined(separator: " | "))")
        baseline.restore(view.settings)
        flowMark("BARGE_ENDE")
    }

    static func conversationKeep(_ view: ChatView) async {
        let report = SweepReport(file: "conversation_keep.txt")
        let marker = StoragePaths().documents.appendingPathComponent("keep_conversation.txt")
        guard let text = try? String(contentsOf: marker, encoding: .utf8),
              let keep = UUID(uuidString: text.trimmed) else {
            report.add("AUFRAEUMEN", "kein_marker")
            return
        }
        var removed = 0
        for conversation in view.store.conversations where conversation.id != keep {
            if view.store.removeConversation(conversation.id) != nil { removed += 1 }
        }
        await view.store.flushPendingSave()
        report.add("AUFRAEUMEN", "entfernt=\(removed) verbleibend=\(view.store.conversations.count)")
        try? FileManager.default.removeItem(at: marker)
        flowMark("KEEP_ENDE")
    }

    static func conversationCleanup(_ view: ChatView) async {
        let report = SweepReport(file: "conversation_cleanup.txt")
        let markers = ["Moment, ich habe eine Frage", "Ist das Problem?"]
        var removed = 0
        for conversation in view.store.conversations {
            let texts = conversation.messages.map(\.text)
            guard texts.contains(where: { text in markers.contains { text.contains($0) } }) else { continue }
            if view.store.removeConversation(conversation.id) != nil { removed += 1 }
        }
        report.add("AUFRAEUMEN", "entfernt=\(removed) verbleibend=\(view.store.conversations.count)")
        flowMark("AUFRAEUMEN fertig")
    }

    private static let cancelWordText = "Das ist eine absichtlich lange Antwort, damit genug Zeit bleibt, "
        + "das Abbruchwort zu sagen. Die Kernfusion verbindet leichte Atomkerne zu schwereren Kernen und setzt "
        + "dabei Energie frei. Auf der Erde versucht man, diesen Vorgang in großen Anlagen nachzubauen, damit "
        + "eines Tages Strom ohne fossile Brennstoffe entsteht. Bis dahin sind noch viele technische Fragen zu "
        + "lösen, zum Beispiel die Hitze im Inneren des Reaktors, die Stabilität des Plasmas und die Materialien, "
        + "die den Belastungen standhalten. Forscherinnen und Forscher arbeiten deshalb weltweit an besseren "
        + "Magneten, neuen Diagnoseverfahren und sicheren Kühlkreisläufen. Gleichzeitig werden kleinere "
        + "Experimente gebaut, um einzelne Bauteile unabhängig voneinander zu testen."

    static func conversationCancelWord(_ view: ChatView) async {
        let report = SweepReport(file: "conversation_cancelword.txt")
        let settings = AppSettings.shared
        let baseline = ShotBaseline(settings, language: .de)
        settings.voice.speakAnswers = true
        settings.voice.cancelWord = "abbrechen"
        view.voice.cancel()
        view.store.newConversation()
        let probeID = view.store.currentID
        try? await Task.sleep(for: .milliseconds(250))
        view.toggleConversationMode()
        let ready = await ProbeWait.until(20) {
            view.probeVoiceState == .recording && HeldMicrophone.shared.isVoiceProcessing
        }
        report.add("START", "bereit=\(ready) abbruchwort=\(settings.spokenCancel) "
                   + "echschutz=\(HeldMicrophone.shared.isVoiceProcessing) sprache=\(L.lang.rawValue)")
        guard ready else {
            view.settings.voice.conversationMode = false
            view.probeAbortVoice()
            if let probeID { _ = view.store.removeConversation(probeID) }
            await view.store.flushPendingSave()
            baseline.restore(settings)
            flowMark("CANCELWORD_ENDE")
            return
        }
        view.speech.stop()
        view.speechInterrupted = false
        flowMark("CANCELWORD_TTS_START")
        view.speech.speak(text: cancelWordText, voiceIdentifier: settings.voice.outputVoice)
        _ = await ProbeWait.until(5) { view.probeSpeaking }
        let cancelled = await ProbeWait.until(30) { view.voiceCancelFeedback }
        let messagesAtCancel = view.store.current?.messages.count ?? -1
        let feedbackSpoken = view.probeSpeaking
        _ = await ProbeWait.until(15) { !view.voiceCancelFeedback }
        let messagesAfter = view.store.current?.messages.count ?? -1
        report.add("ABBRUCH", "erkannt=\(cancelled) feedback=\(feedbackSpoken) "
                   + "spricht_noch=\(view.probeSpeaking) nachrichten_vorher=\(messagesAtCancel) "
                   + "nachher=\(messagesAfter) unterbrochen=\(view.speechInterrupted) zustand=\(view.probeVoiceState)")
        view.settings.voice.conversationMode = false
        view.probeAbortVoice()
        view.speech.stop()
        if let probeID { _ = view.store.removeConversation(probeID) }
        await view.store.flushPendingSave()
        baseline.restore(settings)
        flowMark("CANCELWORD_ENDE")
    }

    static func listenCancelWord(_ view: ChatView) async {
        let report = SweepReport(file: "listen_cancelword.txt")
        let settings = AppSettings.shared
        let baseline = ShotBaseline(settings, language: .de)
        settings.voice.speakAnswers = true
        settings.voice.cancelWord = "abbrechen"
        view.voice.cancel()
        view.store.newConversation()
        let probeID = view.store.currentID
        try? await Task.sleep(for: .milliseconds(250))
        settings.voice.conversationMode = false
        settings.voice.listenMode = true
        view.followListenGate(view.listenGate)
        let ready = await ProbeWait.until(20) {
            view.probeVoiceState == .waiting && HeldMicrophone.shared.isVoiceProcessing
        }
        report.add("START", "bereit=\(ready) abbruchwort=\(settings.spokenCancel) "
                   + "echschutz=\(HeldMicrophone.shared.isVoiceProcessing) sprache=\(L.lang.rawValue)")
        guard ready else {
            settings.voice.listenMode = false
            view.probeAbortVoice()
            if let probeID { _ = view.store.removeConversation(probeID) }
            await view.store.flushPendingSave()
            baseline.restore(settings)
            flowMark("LISTENCANCEL_ENDE")
            return
        }
        view.speech.stop()
        view.speechInterrupted = false
        flowMark("LISTENCANCEL_TTS_START")
        view.speech.speak(text: cancelWordText, voiceIdentifier: settings.voice.outputVoice)
        _ = await ProbeWait.until(5) { view.probeSpeaking }
        view.followListenGate(view.listenGate)
        let listening = await ProbeWait.until(20) {
            view.voice.isCancelSession && HeldMicrophone.shared.isVoiceProcessing
        }
        report.add("HOEREN", "bereit=\(listening) zustand=\(view.probeVoiceState) "
                   + "abbruch=\(view.voice.isCancelSession) echschutz=\(HeldMicrophone.shared.isVoiceProcessing)")
        let cancelled = await ProbeWait.until(30) { view.voiceCancelFeedback }
        let messagesAtCancel = view.store.current?.messages.count ?? -1
        let feedbackSpoken = view.probeSpeaking
        _ = await ProbeWait.until(15) { !view.voiceCancelFeedback }
        let messagesAfter = view.store.current?.messages.count ?? -1
        report.add("ABBRUCH", "erkannt=\(cancelled) hoeren=\(listening) feedback=\(feedbackSpoken) "
                   + "spricht_noch=\(view.probeSpeaking) nachrichten_vorher=\(messagesAtCancel) "
                   + "nachher=\(messagesAfter) unterbrochen=\(view.speechInterrupted) zustand=\(view.probeVoiceState)")
        settings.voice.listenMode = false
        view.probeAbortVoice()
        view.speech.stop()
        if let probeID { _ = view.store.removeConversation(probeID) }
        await view.store.flushPendingSave()
        baseline.restore(settings)
        flowMark("LISTENCANCEL_ENDE")
    }

    static func conversationTurn(_ view: ChatView) async {
        let report = SweepReport(file: "conversation_turn.txt")
        let baseline = ConversationBaseline(view)
        let ready = await conversationReady(view, preparing: { view.store.newConversation() })
        report.add("START", "bereit=\(ready) modus=\(view.settings.voice.conversationMode) "
                   + "zustand=\(view.probeVoiceState) echschutz=\(HeldMicrophone.shared.isVoiceProcessing)")
        guard ready else {
            pauseConversation(view)
            if let probeID = view.store.current?.id {
                _ = view.store.removeConversation(probeID)
            }
            baseline.restore(view.settings)
            flowMark("TURN_ENDE")
            return
        }
        let long = "Das ist eine absichtlich lange Antwort, damit genug Zeit bleibt, um mitten hineinzusprechen. "
            + "Die Kernfusion verbindet leichte Atomkerne zu schwereren Kernen und setzt dabei Energie frei. "
            + "Auf der Erde versucht man, diesen Vorgang in großen Anlagen nachzubauen, damit eines Tages Strom "
            + "ohne fossile Brennstoffe entsteht. Bis dahin sind noch viele technische Fragen zu lösen, zum Beispiel "
            + "die Hitze im Inneren des Reaktors, die Stabilität des Plasmas und die Materialien, die den Belastungen "
            + "standhalten. Forscherinnen und Forscher arbeiten deshalb weltweit an besseren Magneten, neuen "
            + "Diagnoseverfahren und sicheren Kühlkreisläufen. Gleichzeitig werden kleinere Experimente gebaut, um "
            + "einzelne Bauteile unabhängig voneinander zu testen. Der Weg zur kommerziellen Nutzung ist lang, aber "
            + "jeder Schritt liefert wichtige Erkenntnisse über die Physik und die Technik der Zukunft."
        view.speech.stop()
        view.speechInterrupted = false
        flowMark("TURN_TTS_START")
        let ttsStart = ContinuousClock.now
        view.speech.speak(text: long, voiceIdentifier: view.settings.voice.outputVoice)
        _ = await ProbeWait.until(5) { view.probeSpeaking }
        let interrupted = await ProbeWait.until(25) { view.speechInterrupted }
        let interruptionMs = Int(msOf(ttsStart.duration(to: .now)))
        report.add("ZWISCHENRUF", "erkannt=\(interrupted) ms=\(interruptionMs) "
                   + "spricht_noch=\(view.probeSpeaking) zustand=\(view.probeVoiceState) "
                   + "mikrofon=\(HeldMicrophone.shared.isLive)")
        guard interrupted else {
            pauseConversation(view)
            if let probeID = view.store.current?.id {
                _ = view.store.removeConversation(probeID)
            }
            baseline.restore(view.settings)
            flowMark("TURN_ENDE")
            return
        }
        let messagesBefore = view.store.current?.messages.count ?? 0
        let answered = await ProbeWait.until(30) {
            let messages = view.store.current?.messages ?? []
            return messages.count >= messagesBefore + 2
                && messages.last?.role == .assistant
        }
        let messages = view.store.current?.messages ?? []
        let user = messages.last(where: { $0.role == .user })?.text ?? ""
        let assistant = messages.last(where: { $0.role == .assistant })?.text ?? ""
        report.add("NEUE_RUNDE", "fertig=\(answered) nachrichten=\(messages.count) vorher=\(messagesBefore) "
                   + "frage=\(TextLine.oneLine(user, limit: 200)) "
                   + "antwort=\(TextLine.oneLine(assistant, limit: 200)) "
                   + "alarme=\(view.probeAlerts.map { $0.message }.joined(separator: " | "))")
        pauseConversation(view)
        if let probeID = view.store.current?.id {
            _ = view.store.removeConversation(probeID)
        }
        baseline.restore(view.settings)
        flowMark("TURN_ENDE")
    }

    static func ttsPlayback(_ view: ChatView) async {
        let report = SweepReport(file: "tts_play.txt")
        let speech = SpeechSynthesizer()
        let started = ContinuousClock.now
        speech.speak(text: "Die Kernfusion verbindet leichte Atomkerne zu schwereren.")
        var speakingAt = -1
        var endedAt = -1
        for tick in 0...120 {
            if speech.isSpeaking && speakingAt < 0 { speakingAt = tick }
            if speakingAt >= 0, !speech.isSpeaking { endedAt = tick; break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        report.add("TTS_WIEDERGABE", "spricht_ab_s=\(Double(speakingAt) / 4) endet_s=\(Double(endedAt) / 4) "
                   + "ms=\(msOf(started.duration(to: .now))) stimme=\(VoiceCatalog.defaultVoiceName(for: view.settings.language))")
        flowLog.info("TTS fertig")
    }

}
#endif
