#if DEBUG
import UIKit

@MainActor
final class TranscriptBox {
    var text: String?
}

@MainActor
enum DebugFeatureProbe {
    static func run(_ name: String, view: ChatView) async -> Bool {
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        switch name {
        case "webask": await webAsk(view)
        case "phototext": await photoText(view)
        case "editype": await editType(view)
        case "historywipe": await historyWipe(view)
        case "micrec": await micRecord(view)
        case "ttsp": await ttsPlayback(view)
        case "micloop": await micLoop(view)
        case "calwrite": await calendarWrite(view)
        case "webchart": await webChart(view)
        case "tlsretry": await tlsRetry(view)
        default: return false
        }
        return true
    }

    private static func micLoop(_ view: ChatView) async {
        var report = SweepReport()
        let heard = TranscriptBox()
        let voice = VoiceTranscriber()
        let speech = SpeechSynthesizer()
        voice.start(baseURL: view.settings.baseURL, key: view.settings.apiKey,
                    model: view.settings.audioModel) { text in heard.text = text }
        try? await Task.sleep(for: .seconds(1))
        report.add("MIKLOOP_AUFNAHME", "zustand=\(voice.state)")
        speech.speak(text: "Die Kernfusion verbindet leichte Atomkerne.",
                     baseURL: view.settings.baseURL, key: view.settings.apiKey,
                     model: view.settings.audioModel, voice: view.settings.ttsVoice)
        try? await Task.sleep(for: .seconds(9))
        report.add("MIKLOOP_WAEHREND", "aufnahme=\(voice.state) spricht=\(speech.isSpeaking)")
        voice.stopAndTranscribe(baseURL: view.settings.baseURL, key: view.settings.apiKey,
                               model: view.settings.audioModel) { text in heard.text = text }
        var waited = 0
        while voice.state != .idle && waited < 40 {
            try? await Task.sleep(for: .seconds(1))
            waited += 1
        }
        report.add("MIKLOOP_ERGEBNIS", "zustand=\(voice.state) sekunden=\(waited) "
                   + "fehler=\(voice.lastError.map { $0.message } ?? "keine") "
                   + "text=\(heard.text.map { oneLine($0) } ?? "keiner")")
        report.write(into: "mic_loop.txt")
        flowLog.info("MIKLOOP fertig")
    }

    private static func tlsRetry(_ view: ChatView) async {
        var report = SweepReport()
        for (name, base) in [("zertifikat_abgelaufen", "https://expired.badssl.com/compatible-mode/v1"),
                             ("host_unbekannt", "https://gwenmobile-nicht-vorhanden.invalid/v1")] {
            let started = ContinuousClock.now
            var chunks = 0
            do {
                let req = try QwenAPI.makeRequest(baseURL: base, key: "sk-test",
                                                  model: "qwen3.8-flash",
                                                  messages: [ChatMessage(role: .user, text: "x")],
                                                  imageData: [])
                for try await chunk in QwenAPI.streamText(req: req) {
                    chunks += chunk.count
                }
                report.add("TLSRETRY_\(name)", "durchgekommen=ja zeichen=\(chunks) "
                           + "ms=\(msOf(started.duration(to: .now)))")
            } catch {
                report.add("TLSRETRY_\(name)", "zeichen=\(chunks) ms=\(msOf(started.duration(to: .now))) "
                           + "code=\((error as NSError).code) text=\(String(error.localizedDescription.prefix(70)))")
            }
        }
        report.write(into: "tls_retry.txt")
        flowLog.info("TLSRETRY fertig")
    }

    private static func webChart(_ view: ChatView) async {
        var report = SweepReport()
        view.store.newConversation()
        view.input = "Such im Internet nach dem Stromverbrauch in Deutschland "
            + "und stell die Werte als Diagramm dar"
        let t0 = ContinuousClock.now
        await view.send()
        let answer = view.store.current?.messages.last(where: { $0.role == .assistant })
        report.add("WEBDIAGRAMM", "ms=\(msOf(t0.duration(to: .now))) bilder=\(answer?.outImages?.count ?? -1) "
                   + "punkte=\(pointLines(answer?.text ?? "")) quellen=\(answer?.sources?.count ?? -1) "
                   + "text=\(oneLine(answer?.text ?? ""))")
        report.add("WEBDIAGRAMM_KAPSEL", "danach=\(view.webStatus ?? "nil")")
        report.write(into: "web_chart.txt")
        flowLog.info("WEBDIAGRAMM fertig")
    }

    private static func pointLines(_ text: String) -> Int {
        text.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }.count
    }

    private static func calendarWrite(_ view: ChatView) async {
        var report = SweepReport()
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd HH:mm"
        guard let day = Calendar.current.date(byAdding: .day, value: 1, to: Date()),
              let morning = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day) else {
            report.add("KALENDER", "kein datum")
            report.write(into: "calendar_write.txt")
            return
        }
        let created = "GwenMobile Selbsttest"
        let renamed = "GwenMobile Selbsttest 2"
        var create = QwenAPI.CalendarPlan(action: .create)
        create.title = created
        create.start = stamp.string(from: morning)
        create.end = stamp.string(from: morning.addingTimeInterval(3600))
        create.location = "Werkstatt"
        create.alerts = [10, 60]
        do {
            let info = try await CalendarService.perform(create)
            report.add("KALENDER_ANLEGEN", "hinweis=\(oneLine(info)) im_kontext=\(CalendarService.upcomingContext().contains(created))")
            var update = QwenAPI.CalendarPlan(action: .update)
            update.find = created
            update.title = renamed
            update.alerts = [30]
            let changed = try await CalendarService.perform(update)
            report.add("KALENDER_ÄNDERN", "hinweis=\(oneLine(changed)) im_kontext=\(CalendarService.upcomingContext().contains(renamed))")
            var remove = QwenAPI.CalendarPlan(action: .delete)
            remove.find = renamed
            let gone = try await CalendarService.perform(remove)
            report.add("KALENDER_LÖSCHEN", "hinweis=\(oneLine(gone)) noch_im_kontext=\(CalendarService.upcomingContext().contains(renamed))")
        } catch {
            report.addFailure("KALENDER", error)
        }
        report.write(into: "calendar_write.txt")
        flowLog.info("KALENDER fertig")
    }

    private static func micRecord(_ view: ChatView) async {
        var report = SweepReport()
        let heard = TranscriptBox()
        let voice = VoiceTranscriber()
        voice.start(baseURL: view.settings.baseURL, key: view.settings.apiKey,
                    model: view.settings.audioModel) { text in heard.text = text }
        report.add("MIKRO_START", "zustand=\(voice.state) restlich=\(String(describing: voice.remaining))")
        try? await Task.sleep(for: .seconds(4))
        report.add("MIKRO_NACH_VIER", "zustand=\(voice.state) restlich=\(String(describing: voice.remaining))")
        voice.stopAndTranscribe(baseURL: view.settings.baseURL, key: view.settings.apiKey,
                               model: view.settings.audioModel) { text in heard.text = text }
        report.add("MIKRO_STOPP", "zustand=\(voice.state)")
        var waited = 0
        while voice.state != .idle && waited < 40 {
            try? await Task.sleep(for: .seconds(1))
            waited += 1
        }
        report.add("MIKRO_ENDE", "zustand=\(voice.state) sekunden=\(waited) "
                   + "fehler=\(voice.lastError.map { $0.message } ?? "keine") "
                   + "text=\(heard.text.map { oneLine($0) } ?? "keiner")")
        report.write(into: "mic_rec.txt")
        flowLog.info("MIKRO fertig")
    }

    private static func ttsPlayback(_ view: ChatView) async {
        var report = SweepReport()
        let speech = SpeechSynthesizer()
        let started = ContinuousClock.now
        speech.speak(text: "Die Kernfusion verbindet leichte Atomkerne zu schwereren.",
                     baseURL: view.settings.baseURL, key: view.settings.apiKey,
                     model: view.settings.audioModel, voice: view.settings.ttsVoice)
        var speakingAt = -1
        var endedAt = -1
        for tick in 0...120 {
            if speech.isSpeaking && speakingAt < 0 { speakingAt = tick }
            if speakingAt >= 0, !speech.isSpeaking { endedAt = tick; break }
            try? await Task.sleep(for: .milliseconds(250))
        }
        report.add("TTS_WIEDERGABE", "spricht_ab_s=\(Double(speakingAt) / 4) endet_s=\(Double(endedAt) / 4) "
                   + "ms=\(msOf(started.duration(to: .now))) stimme=\(view.settings.ttsVoice) "
                   + "modell=\(view.settings.audioModel)")
        report.write(into: "tts_play.txt")
        flowLog.info("TTS fertig")
    }

    private static func webAsk(_ view: ChatView) async {
        var report = SweepReport()
        view.store.newConversation()
        view.input = "Wer hat den Eurovision Song Contest 2026 gewonnen?"
        let t0 = ContinuousClock.now
        await view.send()
        let answer = view.store.current?.messages.last(where: { $0.role == .assistant })
        report.add("WEBASK", "ms=\(msOf(t0.duration(to: .now))) zeichen=\(answer?.text.count ?? -1) "
                   + "quellen=\(answer?.sources?.count ?? -1) "
                   + "domains=\(answer?.sources?.map(\.domain).joined(separator: ",") ?? "-") "
                   + "anfang=\(oneLine(answer?.text ?? ""))")
        report.add("WEBASK_KAPSEL", "danach=\(view.webStatus ?? "nil")")
        report.add("WEBASK_RENDER", RenderStats.fields())
        report.write(into: "web_ask.txt")
        flowLog.info("WEBASK fertig")
    }

    private static func photoText(_ view: ChatView) async {
        var report = SweepReport()
        view.store.newConversation()
        view.pendingImages = [(image: textShot(), file: nil)]
        view.input = "Übersetze den Text, den du auf dem Foto siehst, wörtlich ins Englische"
        let t0 = ContinuousClock.now
        await view.send()
        let answer = view.store.current?.messages.last(where: { $0.role == .assistant })
        let text = answer?.text ?? ""
        report.add("PHOTOTEXT", "ms=\(msOf(t0.duration(to: .now))) modell=\(answer?.model ?? "-") "
                   + "vision=\(view.settings.visionModel) bilder=\(answer?.outImages?.count ?? -1) "
                   + "zeichen=\(text.count) antwort=\(oneLine(text))")
        report.add("PHOTOTEXT_TREFFER", "coffee=\(text.lowercased().contains("coffee")) "
                   + "cake=\(text.lowercased().contains("cake")) "
                   + "betrag=\(text.contains("14")) english=\(text.lowercased().contains("table"))")
        report.write(into: "photo_text.txt")
        flowLog.info("PHOTOTEXT fertig")
    }

    private static func editType(_ view: ChatView) async {
        var report = SweepReport()
        guard let shot = await view.flowTestPicture() else {
            report.add("EDITYPE", "kein Referenzbild")
            report.write(into: "edit_type.txt")
            return
        }
        view.store.newConversation()
        let baseline = view.store.current?.messages.count ?? 0
        view.pendingImages = [(image: shot, file: nil)]
        view.input = "Mache das Bild etwas heller"
        let started = ContinuousClock.now
        Task { await view.send() }
        try? await Task.sleep(for: .milliseconds(1500))
        var worstStep = 0
        var steps = 0
        for character in "Und bitte mehr Kontrast dazu".unicodeScalars {
            let step = ContinuousClock.now
            view.input.append(Character(character))
            worstStep = max(worstStep, msOf(step.duration(to: .now)))
            steps += 1
            try? await Task.sleep(for: .milliseconds(70))
        }
        report.add("EDITYPE_TYP", "schritte=\(steps) schritt_max_ms=\(worstStep) "
                   + "seit_start_ms=\(msOf(started.duration(to: .now))) eingabe=\"\(view.input)\" "
                   + "render=\(RenderStats.fields())")
        let finished = await wait(forPictureAfter: baseline, in: view)
        report.add("EDITYPE_JOB", "fertig=\(finished) ms=\(msOf(started.duration(to: .now))) "
                   + "nachrichten=\(view.store.current?.messages.count ?? -1) "
                   + "ausgabebilder=\(view.store.current?.messages.last?.outImages?.count ?? -1)")
        let lateStep = ContinuousClock.now
        view.input.append("!")
        report.add("EDITYPE_NACH", "eingabe_ms=\(msOf(lateStep.duration(to: .now))) "
                   + "text=\"\(view.input)\" render=\(RenderStats.fields())")
        report.write(into: "edit_type.txt")
        flowLog.info("EDITYPE fertig")
    }

    private static func historyWipe(_ view: ChatView) async {
        var report = SweepReport()
        let store = view.store
        let stored = store.media.imageFileNames().first
        if let stored, let seeded = store.currentID {
            store.appendMessage(ChatMessage(role: .user, text: "Frage mit Bild",
                                            images: [Attachment(file: stored)]), to: seeded)
            store.appendAssistant("Antwort mit Bild", model: "probe", elapsed: nil, to: seeded,
                                  outImages: [Attachment(file: stored)])
        }
        let conversationsBefore = store.conversations.count
        let filesBefore = store.media.imageFileNames().count
        let first = store.conversations.last?.id
        if let first { store.cleaner.deleteConversation(first) }
        report.add("EINZELLÖSCHUNG", "vorher=\(conversationsBefore) nachher=\(store.conversations.count) "
                   + "beleg=\(store.cleaner.receipt?.conversations.count ?? -1) "
                   + "freigegebene_dateien=\(store.cleaner.receipt?.freedFiles ?? -1) "
                   + "datei_weg=\(stored.map { String(store.media.data(named: $0) == nil) } ?? "-")")
        store.cleaner.undoLast()
        report.add("EINZELLÖSCHUNG_UNDO", "unterhaltungen=\(store.conversations.count) "
                   + "dateien=\(store.media.imageFileNames().count) vorher_dateien=\(filesBefore) "
                   + "wieder_da=\(stored.map { String(store.media.data(named: $0) != nil) } ?? "-")")
        view.store.newConversation()
        guard let doomed = store.currentID else {
            report.add(" abbruch", "keine aktuelle unterhaltung")
            report.write(into: "history_wipe.txt")
            return
        }
        store.appendAssistant("Löschtest-Antwort", model: "probe", elapsed: nil, to: doomed)
        let messageCount = store.conversations.first { $0.id == doomed }?.messages.count ?? -1
        if let last = store.conversations.first(where: { $0.id == doomed })?.messages.last {
            store.cleaner.deleteMessage(last.id, in: doomed)
        }
        report.add("NACHRICHT_LÖSCHUNG", "vorher=\(messageCount) "
                   + "nachher=\(store.conversations.first { $0.id == doomed }?.messages.count ?? -1)")
        store.cleaner.undoLast()
        report.add("NACHRICHT_UNDO",
                   "nachher=\(store.conversations.first { $0.id == doomed }?.messages.count ?? -1)")
        let openBefore = store.currentID
        store.cleaner.deleteAllConversations()
        report.add("ALLE_LÖSCHUNG", "unterhaltungen=\(store.conversations.count) "
                   + "aktuellVorher=\(String(describing: openBefore)) aktuell=\(String(describing: store.currentID)) "
                   + "beleg=\(store.cleaner.receipt?.conversations.count ?? -1) "
                   + "dateien=\(store.cleaner.receipt?.freedFiles ?? -1) "
                   + "bytes=\(store.cleaner.receipt?.freedBytes ?? -1) "
                   + "speicher=\(store.cleaner.usage.summaryText)")
        store.cleaner.undoLast()
        report.add("ALLE_UNDO", "unterhaltungen=\(store.conversations.count) "
                   + "aktuell=\(String(describing: store.currentID)) wiederher=\(store.currentID == openBefore)")
        store.cleaner.deleteAllConversations()
        try? await Task.sleep(for: .seconds(7))
        report.add("ALLE_ENDGÜLTIG", "unterhaltungen=\(store.conversations.count) "
                   + "beleg_offen=\(store.cleaner.receipt != nil)")
        let trashFiles = (try? FileManager.default.contentsOfDirectory(atPath: store.media.paths.trash.path)) ?? []
        report.add("TRASH_LEER", "dateien=\(trashFiles.count)")
        report.write(into: "history_wipe.txt")
        flowLog.info("HISTORYWIPE fertig")
    }

    private static func wait(forPictureAfter index: Int, in view: ChatView) async -> Bool {
        let deadline = Date().addingTimeInterval(240)
        while Date() < deadline {
            let messages = view.store.current?.messages ?? []
            if messages.count > index, messages.dropFirst(index).contains(where: { $0.outImages?.isEmpty == false }) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }

    private static func textShot() -> UIImage {
        let canvas = CGSize(width: 1000, height: 700)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: canvas))
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 14
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 44, weight: .semibold),
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraph,
            ]
            "ZWEI KAFFEE UND EIN STÜCK KUCHEN\nRECHNUNG: 14,80 EURO\nTISCH NUMMER SIEBEN"
                .draw(in: CGRect(x: 60, y: 140, width: canvas.width - 120, height: canvas.height - 280),
                      withAttributes: attributes)
        }
    }

    private static func oneLine(_ text: String) -> String {
        String(text.prefix(160)).replacingOccurrences(of: "\n", with: " ")
    }
}
#endif
