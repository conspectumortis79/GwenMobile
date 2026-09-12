#if DEBUG
import UIKit
import EventKit

@MainActor
struct SweepReport {
    var lines: [String] = []

    mutating func add(_ section: String, _ detail: String) {
        lines.append("\(section): \(detail)")
    }

    mutating func addFailure(_ section: String, _ error: Error) {
        let ns = error as NSError
        let host = (ns.userInfo[NSURLErrorFailingURLStringErrorKey] as? String) ?? (ns.userInfo[NSURLErrorFailingURLErrorKey].map { String(describing: $0) } ?? "-")
        lines.append("\(section): FEHLER domain=\(ns.domain) code=\(ns.code) url=\(host.prefix(70)) text=\(error.localizedDescription.prefix(60))")
    }

    func write(into file: String) {
        let url = StoragePaths().documents.appendingPathComponent(file)
        try? lines.joined(separator: "\n").data(using: .utf8)?.write(to: url)
    }
}

enum RealtimeProbe {
    static var bigImage: String { flowTestBigImage }

    static func silencePCM(seconds: Int) -> Data {
        Data(count: seconds * WAVCodec.targetSampleRate * WAVCodec.bytesPerFrame)
    }
}

extension ChatView {
    func runSweep() async {
        UIApplication.shared.isIdleTimerDisabled = true
        var report = SweepReport()
        let baseURL = settings.baseURL
        let key = settings.apiKey
        report.add("KONFIG", "schluessel=\(settings.isConfigured) chat=\(settings.chatModel) vision=\(settings.visionModel) bild=\(settings.imageModel) audio=\(settings.audioModel) sprache=\(L.lang.rawValue) basis=\(baseURL)")

        do {
            let models = try await QwenAPI.fetchModels(baseURL: baseURL, key: key)
            report.add("MODELLE", "anzahl=\(models.count) erste=\(models.prefix(3).joined(separator: ","))")
        } catch { report.addFailure("MODELLE", error) }

        do {
            let answer = try await askOnce("Was ist die Hauptstadt von Frankreich?")
            report.add("CHAT_WISSEN", "zeichen=\(answer.count) suchToken=\(answer.contains(SearchMarker.token)) anfang=\(prefix(answer))")
        } catch { report.addFailure("CHAT_WISSEN", error) }

        do {
            let answer = try await askOnce("Aktuelle Nachrichten")
            report.add("CHAT_SUCHHINWEIS", "suchToken=\(answer.contains(SearchMarker.token)) anfang=\(prefix(answer))")
        } catch { report.addFailure("CHAT_SUCHHINWEIS", error) }

        for lauf in 1...3 {
            do {
                let urls = try await WebSearch.search("aktuelle nachrichten")
                var hits: [WebHit] = []
                for u in urls {
                    if let hit = try? await WebSearch.fetchText(u) { hits.append(hit) }
                }
                report.add("WEBPFAD\(lauf)", "urls=\(urls.count) geleseneSeiten=\(hits.count) hosts=\(hits.map { $0.domain }.joined(separator: ","))")
                if hits.count >= 2 {
                    let req = try WebSearch.makeAnswerRequest(baseURL: baseURL, key: key,
                                                             model: settings.chatModel,
                                                             question: "Was sind die wichtigsten Nachrichten heute?",
                                                             hits: hits)
                    let answer = try await ChatRunner.shared.run(req) { _ in }
                    report.add("WEBANTWORT\(lauf)", "zeichen=\(answer.count) anfang=\(prefix(answer))")
                }
            } catch { report.addFailure("WEBPFAD\(lauf)", error) }
            try? await Task.sleep(for: .seconds(2))
        }

        store.newConversation()
        input = "Aktuelle Nachrichten"
        await send()
        let uiAnswer = store.current?.messages.last(where: { $0.role == .assistant })
        report.add("UI_SUCHE", "quellen=\(uiAnswer?.sources?.count ?? -1) zeichen=\(uiAnswer?.text.count ?? -1) anfang=\(prefix(uiAnswer?.text ?? ""))")
        report.add("UI_SUCHE_KAPSEL", "danach=\(webStatus ?? "nil")")
        store.newConversation()
        input = "Was ist die Hauptstadt von Frankreich?"
        await send()
        let uiPlain = store.current?.messages.last(where: { $0.role == .assistant })
        report.add("UI_WISSEN", "quellen=\(uiPlain?.sources?.count ?? -1) zeichen=\(uiPlain?.text.count ?? -1) anfang=\(prefix(uiPlain?.text ?? ""))")

        do {
            let followUp = [ChatMessage(role: .user, text: "Was sind die Hauptursachen der Klimaerwärmung?"),
                            ChatMessage(role: .assistant,
                                        text: "Die Hauptursachen sind die Verbrennung von Kohle, Öl und Gas, Industrie, Landwirtschaft und Abholzung."),
                            ChatMessage(role: .user, text: "und in Deutschland?")]
            report.add("KONTEXT_ERKENNT",
                       "notwendig=\(FollowUpResolver.needsContext("und in Deutschland?"))"
                       + " alleinstehend=\(FollowUpResolver.needsContext("Was ist die Hauptstadt von Frankreich?"))")
            for lauf in 1...3 {
                let raw = try await QwenAPI.resolveQuery(baseURL: baseURL, key: key,
                                                         model: settings.chatModel, history: followUp)
                let query = FollowUpResolver.sanitize(raw ?? "")
                report.add("KONTEXT_FRAGE\(lauf)",
                           "nutzbar=\(FollowUpResolver.isUsable(query, insteadOf: "und in Deutschland?")) abfrage=\(query)")
            }
        } catch { report.addFailure("KONTEXT_FRAGE", error) }

        store.newConversation()
        input = "Wie viele Einwohner hat Deutschland in den letzten Jahren jeweils gehabt?"
        await send()
        let role1 = store.current?.messages.last(where: { $0.role == .assistant })
        report.add("KONTEXT_ROLLE1", "zeichen=\(role1?.text.count ?? -1) quellen=\(role1?.sources?.count ?? -1) anfang=\(prefix(role1?.text ?? ""))")
        input = "mach daraus ein diagramm"
        await send()
        let chartFromAnswer = store.current?.messages.last(where: { $0.role == .assistant })
        report.add("KONTEXT_DIAGRAMM_DARAUS", "bilder=\(chartFromAnswer?.outImages?.count ?? -1) zeichen=\(chartFromAnswer?.text.count ?? -1) quellen=\(chartFromAnswer?.sources?.count ?? -1) anfang=\(prefix(chartFromAnswer?.text ?? ""))")

        store.newConversation()
        input = "Was ist die Hauptstadt von Frankreich?"
        await send()
        input = "Und in Österreich?"
        await send()
        let shortFollow = store.current?.messages.last(where: { $0.role == .assistant })
        report.add("KONTEXT_KURZFRAGE", "zeichen=\(shortFollow?.text.count ?? -1) quellen=\(shortFollow?.sources?.count ?? -1) anfang=\(prefix(shortFollow?.text ?? ""))")

        store.newConversation()
        input = "Such im Internet nach dem Stromverbrauch in Deutschland und stell die Werte als Diagramm dar"
        await send()
        let webChart = store.current?.messages.last(where: { $0.role == .assistant })
        report.add("KETTE_SUCHE_DIAGRAMM", "bilder=\(webChart?.outImages?.count ?? -1) zeichen=\(webChart?.text.count ?? -1) quellen=\(webChart?.sources?.count ?? -1) anfang=\(prefix(webChart?.text ?? ""))")

        let status = EKEventStore.authorizationStatus(for: .event)
        report.add("KALENDER_RECHT", "status=\(status.rawValue)")
        report.add("KALENDER_KONTEXT", "zeichen=\(CalendarService.upcomingContext().count)")
        do {
            if let plan = try await QwenAPI.calendarPlan(baseURL: baseURL, key: key, model: settings.chatModel,
                                                        instruction: "Leg bitte morgen um 14 Uhr einen Zahnarzttermin für eine Stunde an",
                                                        calendars: CalendarService.calendarsContext()) {
                report.add("KALENDER_PLAN", "aktion=\(plan.action) titel=\(plan.title ?? "-") start=\(plan.start ?? "-") end=\(plan.end ?? "-") alerten=\(plan.alerts.map { String(describing: $0) } ?? "-") kalender=\(plan.calendar ?? "-")")
            } else {
                report.add("KALENDER_PLAN", "keinPlan")
            }
        } catch { report.addFailure("KALENDER_PLAN", error) }

        let stored = store.media.data(named: RealtimeProbe.bigImage)
        report.add("SANDBOX_BILD", "vorhanden=\(stored != nil) bytes=\(stored?.count ?? -1)")

        if let stored, let image = await decodedThumbnail(stored) {
            store.newConversation()
            pendingImages = [(image: image, file: RealtimeProbe.bigImage)]
            input = "Mache das Bild etwas heller"
            let beforeEdit = store.current?.messages.count ?? 0
            await send()
            let edited = assistantMessage(afterIndex: beforeEdit)
            report.add("BILDBEARBEITUNG", "ausgabebilder=\(edited?.outImages?.count ?? -1) antwortzeichen=\(edited?.text.count ?? -1)")
        }

        do {
            let urls = try await QwenAPI.generateImage(req: QwenAPI.makeImageRequest(baseURL: baseURL, key: key,
                                                                                   model: settings.imageModel,
                                                                                   prompt: "Eine rote Tasse auf einem Tisch",
                                                                                   inputImages: []))
            report.add("BILDERGENERIERUNG", "urls=\(urls.count)")
        } catch { report.addFailure("BILDERGENERIERUNG", error) }

        do {
            let pcm = try await SpeechSynthesizer.synthesize(text: "Hallo", baseURL: baseURL, key: key,
                                                            model: settings.audioModel, voice: settings.ttsVoice)
            report.add("TTS_CLOUD", "pcmBytes=\(pcm.count) wavBytes=\(WAVCodec.wav(fromPCM: pcm, sampleRate: SpeechSynthesizer.outputSampleRate).count)")
        } catch { report.addFailure("TTS_CLOUD", error) }

        do {
            let transcript = try await VoiceTranscriber.transcribe(pcm: RealtimeProbe.silencePCM(seconds: 1),
                                                                   baseURL: baseURL, key: key, model: settings.audioModel)
            report.add("ASR_TRANSPORT", "protokollZeichen=\(transcript.count)")
        } catch { report.addFailure("ASR_TRANSPORT", error) }

        let paths = StoragePaths()
        let reloaded = ChatStore(media: MediaStore(paths: paths), paths: paths)
        report.add("PERSISTENZ", "unterhaltungenNeuGeladen=\(reloaded.conversations.count) nachRunden=\(store.conversations.count)")
        report.add("OBERFLAECHE", "unterhaltungen=\(store.conversations.count) nachrichten=\(store.conversations.reduce(0) { $0 + $1.messages.count })")

        report.write(into: "flow_sweep.txt")
        flowLog.info("SWEEP bericht geschrieben")
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func askOnce(_ text: String) async throws -> String {
        let req = try QwenAPI.makeRequest(baseURL: settings.baseURL, key: settings.apiKey,
                                          model: settings.chatModel,
                                          messages: [ChatMessage(role: .user, text: text)], imageData: [])
        return try await ChatRunner.shared.run(req) { _ in }
    }

    private func assistantMessage(afterIndex index: Int) -> ChatMessage? {
        guard let messages = store.current?.messages, messages.count > index else { return nil }
        return messages.dropFirst(index).last { $0.role == .assistant }
    }

    private func decodedThumbnail(_ data: Data) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            MediaStore.thumbnail(data, maxPixel: ImagePolicy.uploadMaxPixel)
        }.value
    }

    func runCapabilityProbe() async {
        UIApplication.shared.isIdleTimerDisabled = true
        var report = SweepReport()
        let loaded = settings.availableModels.isEmpty
            ? (try? await QwenAPI.fetchModels(baseURL: settings.baseURL, key: settings.apiKey)) ?? []
            : settings.availableModels
        let textModels = ModelFilter.textCandidates(loaded)
        report.add("SONDE_LISTE", "gesamt=\(loaded.count) text=\(textModels.count) chat=\(settings.chatModel) vision=\(settings.visionModel) gewaehlt=\(settings.chatThinkingLevel.rawValue)")
        let caps = await QwenModelProber().discover(baseURL: settings.baseURL, key: settings.apiKey,
                                                    models: textModels)
        let stored = settings.modelCaps.merging(caps) { _, new in new }
        for model in textModels {
            let found = caps[model] ?? ModelCapabilities()
            report.add("SONDE_\(model)",
                       "stufen=\(found.thinking.levels.map { $0.rawValue }.joined(separator: ",")) "
                           + "abschaltbar=\(found.thinking.canSwitchOff) "
                           + "vision=\(found.vision.rawValue) "
                           + "angebot=\(found.thinking.offeredLevels.map { $0.rawValue }.joined(separator: ",")) "
                           + "richtung=\(Self.directiveSummary(found.thinking.directive(for: settings.chatThinkingLevel))) "
                           + "aus=\(Self.directiveSummary(found.thinking.directive(for: .off)))")
        }
        report.add("SONDE_ERNET", "vollstaendig=\(caps.count) "
                   + "visionJa=\(caps.filter { $0.value.vision == .supported }.count) "
                   + "visionNein=\(caps.filter { $0.value.vision == .rejected }.count) "
                   + "visionsListe=\(ModelFilter.visionCandidates(loaded, caps: stored).joined(separator: ","))")
        report.write(into: "model_caps_probe.txt")
        flowLog.info("CAPSPROBE bericht geschrieben")
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private static func directiveSummary(_ directive: ThinkingDirective) -> String {
        switch directive {
        case .nothing: return "nichts"
        case .effort(let level): return "reasoning_effort=\(level.rawValue)"
        case .suppressThinking: return "enable_thinking=false"
        }
    }

    func runAirDropProbe(seconds: Int = 900, graceSeconds: Int = 10) async {
        UIApplication.shared.isIdleTimerDisabled = true
        var report = SweepReport()
        var attachments = store.conversations.flatMap { c in c.messages.flatMap { $0.outImages ?? [] } }
        report.add("AIRDROP_VERLAUF", "bilder=\(attachments.count)")
        if attachments.isEmpty {
            store.newConversation()
            input = "Erzeuge ein Bild von einer roten Tasse auf einem Holztisch"
            await send()
            attachments = store.current?.messages.flatMap { $0.outImages ?? [] } ?? []
            report.add("AIRDROP_ERZEUGT", "bilder=\(attachments.count)")
        }
        guard let att = attachments.last, let url = store.media.storedURL(for: att) else {
            report.add("AIRDROP_DATEI", "keinBildGefunden")
            report.write(into: "airdrop_probe.txt")
            UIApplication.shared.isIdleTimerDisabled = false
            return
        }
        let bytes = (try? Data(contentsOf: url))?.count ?? -1
        report.add("AIRDROP_DATEI", "name=\(url.lastPathComponent) endung=\(url.pathExtension) bytes=\(bytes)")
        do {
            try Presenter.share(url: url)
        } catch { report.addFailure("AIRDROP_FENSTER", error) }
        var gefunden: UIActivityViewController?
        for _ in 0..<50 {
            try? await Task.sleep(for: .milliseconds(200))
            if let sheet = Presenter.topViewController as? UIActivityViewController { gefunden = sheet; break }
        }
        guard let sheet = gefunden else {
            report.add("AIRDROP_BEOBACHTUNG", "keinSheet")
            report.write(into: "airdrop_probe.txt")
            UIApplication.shared.isIdleTimerDisabled = false
            return
        }
        let events = ShareProbeEvents()
        let observer = ShareFlowObserver(sheet: sheet, events: events)
        for lauf in 0..<(seconds * 5) {
            try? await Task.sleep(for: .milliseconds(200))
            observer.tick()
            if lauf * 200 >= graceSeconds * 1000, observer.sheetIsGone { break }
        }
        report.add("AIRDROP_BEOBACHTUNG", "ereignisse=\(events.all.count)")
        for line in events.all { report.add("BEOB", line) }
        report.add("AIRDROP_ENDE", "chatSichtbarWieder=\(observer.sheetIsGone)")
        report.write(into: "airdrop_probe.txt")
        flowLog.info("AIRDROPPROBE bericht geschrieben")
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func runChartGuardProbe() async {
        UIApplication.shared.isIdleTimerDisabled = true
        var report = SweepReport()
        store.newConversation()
        input = "Wie viele Einwohner hat Deutschland und Österreich in den letzten Jahren jeweils gehabt?"
        await send()
        let basis = store.current?.messages.last(where: { $0.role == .assistant })
        report.add("GUET_BASIS", "zeichen=\(basis?.text.count ?? -1) quellen=\(basis?.sources?.count ?? -1)")
        input = "mach daraus ein diagramm"
        await send()
        let chart = store.current?.messages.last(where: { $0.role == .assistant })
        report.add("GUET_DIAGRAMM", "bilder=\(chart?.outImages?.count ?? 0)")
        let rueckfragen = [
            "Ich will wissen, woher du die Statistik für Österreich hast, die du in dem Diagramm eingetragen hast.",
            "Weißt du noch, welche Werte du eingetragen hast im Diagramm? Bitte zeige sie mir.",
            "mach das diagramm bitte neu mit den werten von 2025"
        ]
        for (lauf, frage) in rueckfragen.enumerated() {
            input = frage
            await send()
            let answer = store.current?.messages.last(where: { $0.role == .assistant })
            report.add("GUET_FRAGE\(lauf)", "bilder=\(answer?.outImages?.count ?? 0) "
                       + "zeichen=\(answer?.text.count ?? -1) text=\(Self.oneLine(answer?.text ?? ""))")
        }
        report.write(into: "chart_guard.txt")
        flowLog.info("CHARTGUARD bericht geschrieben")
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func runExportProbe() async {
        UIApplication.shared.isIdleTimerDisabled = true
        var report = SweepReport()
        store.newConversation()
        input = "Was ist die Hauptstadt von Frankreich? Nenne zwei Meilensteine mit Quellen."
        await send()
        let messages = store.current?.messages ?? []
        guard let answer = messages.last(where: { $0.role == .assistant }) else {
            report.add("EXPORT_DATEI", "keineAntwort")
            report.write(into: "export_probe.txt")
            UIApplication.shared.isIdleTimerDisabled = false
            return
        }
        let question = Self.question(for: answer, in: messages) ?? ""
        report.add("EXPORT_FRAGE", "frage=\(question) antwortzeichen=\(answer.text.count) quellen=\(answer.sources?.count ?? -1)")
        do {
            let url = try AnswerExporter().write(text: answer.text, sources: answer.sources ?? [],
                                                 question: question, model: answer.model,
                                                 elapsed: answer.elapsed, time: Self.timeString(answer.date))
            let html = try String(contentsOf: url, encoding: .utf8)
            report.add("EXPORT_DATEI", "name=\(url.lastPathComponent) bytes=\(html.utf8.count) "
                       + "htmlAbschnitte=\(html.components(separatedBy: "<p>").count - 1) "
                       + "fett=\(html.contains("<strong>")) rohesMarkdown=\(html.contains("**")) "
                       + "links=\(html.components(separatedBy: "<a href=\"").count - 1)")
            try Presenter.share(url: url)
        } catch { report.addFailure("EXPORT_DATEI", error) }
        report.write(into: "export_probe.txt")
        flowLog.info("EXPORTPROBE bericht geschrieben")
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func runSearchOnceProbe() async {
        UIApplication.shared.isIdleTimerDisabled = true
        var report = SweepReport()
        for (lauf, frage) in ["Wann wurde die Bundesrepublik Deutschland gegründet?",
                               "Wie viele Arbeitslose gab es in Deutschland in den letzten zwei Jahren?"].enumerated() {
            let t0 = ContinuousClock.now
            do {
                let urls = try await WebSearch.search(frage)
                report.add("STUFE_SUCHE\(lauf)", "urls=\(urls.count) hosts=\(urls.map { WebSearch.domain(of: $0) }.joined(separator: ","))"
                           + " ms=\(msOf(t0.duration(to: .now)))")
                for u in urls {
                    let t1 = ContinuousClock.now
                    do {
                        let hit = try await WebSearch.fetchText(u)
                        report.add("STUFE_SEITE\(lauf)", "host=\(hit.domain) zeichen=\(hit.text.count) ms=\(msOf(t1.duration(to: .now)))")
                    } catch { report.addFailure("STUFE_SEITE\(lauf)_\(WebSearch.domain(of: u))", error) }
                }
            } catch { report.addFailure("STUFE_SUCHE\(lauf)", error) }
        }
        store.newConversation()
        input = "Wie viele Arbeitslose gab es in Deutschland in den letzten zwei Jahren?"
        await send()
        let answer = store.current?.messages.last(where: { $0.role == .assistant })
        report.add("SUCHE_ONCE", "zeichen=\(answer?.text.count ?? -1) quellen=\(answer?.sources?.count ?? -1) "
                   + "nachrichten=\(store.current?.messages.count ?? -1) kapsel=\(webStatus ?? "nil")")
        report.write(into: "search_once.txt")
        flowLog.info("SEARCHONCE bericht geschrieben")
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func runChartProbe() async {
        UIApplication.shared.isIdleTimerDisabled = true
        var report = SweepReport()

        store.newConversation()
        input = "Wie viele Einwohner hat Deutschland in den letzten Jahren jeweils gehabt?"
        await send()
        let prior = store.current?.messages.last(where: { $0.role == .assistant })
        report.add("PROBE_ROLLE1", "zeichen=\(prior?.text.count ?? -1) quellen=\(prior?.sources?.count ?? -1)")
        input = "mach daraus ein diagramm"
        await send()
        let chart = store.current?.messages.last(where: { $0.role == .assistant })
        report.add("PROBE_DARAUS",
                   "punkte=\(Self.dataPoints(chart?.text ?? "")) bilder=\(chart?.outImages?.count ?? -1) "
                   + "quellen=\(chart?.sources?.count ?? -1) text=\(Self.oneLine(chart?.text ?? ""))")

        store.newConversation()
        input = "Wie hoch ist die Arbeitslosenquote in Deutschland gerade?"
        await send()
        let first = store.current?.messages.last(where: { $0.role == .assistant })
        report.add("PROBE_SUCHE1", "zeichen=\(first?.text.count ?? -1) quellen=\(first?.sources?.count ?? -1)")
        input = "und in österreich?"
        await send()
        let second = store.current?.messages.last(where: { $0.role == .assistant })
        report.add("PROBE_SUCHE2", "zeichen=\(second?.text.count ?? -1) quellen=\(second?.sources?.count ?? -1) "
                   + "text=\(Self.oneLine(second?.text ?? ""))")

        store.newConversation()
        input = "Such im Internet nach dem Stromverbrauch in Deutschland und stell die Werte als Diagramm dar"
        await send()
        let chain = store.current?.messages.last(where: { $0.role == .assistant })
        report.add("PROBE_KETTE",
                   "punkte=\(Self.dataPoints(chain?.text ?? "")) bilder=\(chain?.outImages?.count ?? -1) "
                   + "quellen=\(chain?.sources?.count ?? -1) text=\(Self.oneLine(chain?.text ?? ""))")

        report.write(into: "chart_probe.txt")
        flowLog.info("CHARTPROBE bericht geschrieben")
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func runPictureSweep() async {
        UIApplication.shared.isIdleTimerDisabled = true
        var report = SweepReport()
        PictureProbe.materialise(in: store.media)
        let wanted = PictureProbe.all
        let missing = wanted.filter { store.media.data(named: $0.file) == nil }
        report.add("SETUP", "bild=\(settings.imageModel) vision=\(settings.visionModel) chat=\(settings.chatModel) "
                   + "kap=\(ConversationMemory.maxPictures) fehlend=\(missing.map { $0.file }.joined(separator: ","))")
        for fixture in PictureProbe.all {
            if let picture = store.media.decodedDisplayImage(named: fixture.file) {
                report.add("FIXTURE_\(fixture.file)", "\(PictureProbe.rgbText(picture)) form=\(fixture.shape) "
                           + "farbe=\(fixture.colour)")
            }
        }
        guard missing.isEmpty, settings.isConfigured else {
            report.add("ABBRUCH", "testbilder fehlen oder schluessel fehlt")
            report.write(into: PictureProbe.report)
            UIApplication.shared.isIdleTimerDisabled = false
            return
        }

        store.newConversation()
        let chatID = store.current?.id
        for fixture in PictureProbe.fixtures { await postPicture(fixture) }
        let baseline = store.current?.messages ?? []
        let remembered = ConversationMemory.rememberedImages(from: baseline).map(\.file)
        report.add("BASELINE", "nachrichten=\(baseline.count) erinnert=\(remembered.count) "
                   + "reihenfolge=\(remembered.joined(separator: ","))")

        for testCase in PictureProbe.cases {
            restore(messages: baseline, into: chatID)
            for fixture in testCase.extra { await postPicture(fixture) }
            let history = store.current?.messages ?? []
            report.add("AUSWAHL_\(testCase.name)",
                       "erinnert=\(ConversationMemory.rememberedImages(from: history).map { $0.file }.joined(separator: ",")) "
                       + "anhang=\(testCase.attached?.file ?? "-") kap=\(ConversationMemory.maxPictures)")
            pendingImages = []
            if let attached = testCase.attached,
               let picture = store.media.decodedDisplayImage(named: attached.file) {
                pendingImages = [(image: picture, file: attached.file)]
            }
            input = testCase.instruction
            await send()
            let reply = store.current?.messages.last ?? ChatMessage(role: .assistant, text: "keine antwort")
            let file = (reply.outImages ?? []).first?.file ?? ""
            let folded = PictureProbe.folded(reply.text)
            let colourMatched = testCase.colours.contains { folded.contains($0) }
            if !testCase.expectsPicture {
                report.add("FALL_\(testCase.name)", "bild_erwartet=nein out=\(file.isEmpty ? "none" : file) "
                           + "form_ok=\(folded.contains(testCase.shape)) farbe_ok=\(colourMatched) "
                           + "text=\(prefix(reply.text))")
                continue
            }
            let picture = file.isEmpty ? nil : store.media.exportImage(named: file)
            let shape = await describePicture(file: file, question: testCase.question)
            let count = await describePicture(file: file, question: PictureProbe.objectCountQuestion)
            let look = shape + " " + count
            let seen = PictureProbe.folded(look)
            let foreign = PictureProbe.foreignShapes(except: testCase.shape)
            report.add("FALL_\(testCase.name)",
                       "datei=\(file) gemessen=\(picture.map { PictureProbe.rgbText($0) } ?? "-") "
                           + "form_erwartet=\(testCase.shape) form_ok=\(seen.contains(testCase.shape)) "
                           + "farben_erwartet=\(testCase.colours.joined(separator: "|")) "
                           + "farbe_ok=\(testCase.colours.contains { seen.contains($0) }) "
                           + "fremde_formen_ok=\(!foreign.contains { seen.contains($0) }) "
                           + "sicht=\(String(look.prefix(150)).replacingOccurrences(of: "\n", with: " "))")
        }
        report.write(into: PictureProbe.report)
        flowLog.info("PICTURESWEEP bericht geschrieben")
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func postPicture(_ fixture: PictureProbe.Fixture) async {
        guard let picture = store.media.decodedDisplayImage(named: fixture.file) else { return }
        pendingImages = [(image: picture, file: fixture.file)]
        input = ""
        await send()
    }

    private func restore(messages: [ChatMessage], into id: UUID?) {
        guard let index = store.conversations.firstIndex(where: { $0.id == id }) else { return }
        store.conversations[index].messages = messages
    }

    private func describePicture(file: String, question: String) async -> String {
        guard let data = store.media.data(named: file) else { return "kein bild geladen" }
        do {
            let req = try QwenAPI.makeRequest(baseURL: settings.baseURL, key: settings.apiKey,
                                              model: settings.visionModel,
                                              messages: [ChatMessage(role: .user, text: question,
                                                                     images: [Attachment(file: file)])],
                                              imageData: [data])
            return try await ChatRunner.shared.run(req) { _ in }
        } catch {
            return "FEHLER " + error.localizedDescription
        }
    }

    private static func dataPoints(_ text: String) -> Int {
        text.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }.count
    }

    private static func oneLine(_ text: String) -> String {
        String(text.prefix(130)).replacingOccurrences(of: "\n", with: " ")
    }

    private func prefix(_ text: String) -> String {
        String(text.prefix(70)).replacingOccurrences(of: "\n", with: " ")
    }
}

enum PictureProbe {
    static let report = "picture_sweep.txt"

    enum Kind {
        case ellipse, rectangle, triangle, star, roundedRectangle
    }

    struct Fixture {
        let file: String
        let shape: String
        let colour: String
        let canvas: CGSize
        let background: UIColor
        let object: UIColor
        let kind: Kind

        func image() -> UIImage {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: canvas, format: format).image { context in
                background.setFill()
                context.fill(CGRect(origin: .zero, size: canvas))
                object.setFill()
                let path = UIBezierPath()
                switch kind {
                case .ellipse:
                    let box = inset(0.34)
                    path.append(UIBezierPath(roundedRect: box, cornerRadius: box.width / 2))
                case .rectangle:
                    path.append(UIBezierPath(rect: inset(0.28)))
                case .roundedRectangle:
                    path.append(UIBezierPath(roundedRect: inset(0.3), cornerRadius: canvas.width * 0.03))
                case .triangle:
                    let box = inset(0.22)
                    path.move(to: CGPoint(x: box.midX, y: box.minY))
                    path.addLine(to: CGPoint(x: box.maxX, y: box.maxY))
                    path.addLine(to: CGPoint(x: box.minX, y: box.maxY))
                    path.close()
                case .star:
                    star(into: path)
                }
                path.fill()
            }
        }

        private func inset(_ ratio: CGFloat) -> CGRect {
            let side = min(canvas.width, canvas.height)
            let box = CGSize(width: side * (1 - ratio * 2), height: side * (1 - ratio * 2))
            return CGRect(x: (canvas.width - box.width) / 2, y: (canvas.height - box.height) / 2,
                          width: box.width, height: box.height)
        }

        private func star(into path: UIBezierPath) {
            let box = inset(0.18)
            let centre = CGPoint(x: box.midX, y: box.midY)
            let outer = min(box.width, box.height) / 2
            for point in 0..<10 {
                let radius = point.isMultiple(of: 2) ? outer : outer * 0.42
                let angle = -CGFloat.pi / 2 + CGFloat(point) * .pi / 5
                let at = CGPoint(x: centre.x + radius * cos(angle), y: centre.y + radius * sin(angle))
                if point == 0 { path.move(to: at) } else { path.addLine(to: at) }
            }
            path.close()
        }

        func data() -> Data? {
            image().jpegData(compressionQuality: ImagePolicy.jpegQuality)
        }
    }

    struct TestCase {
        let name: String
        var attached: Fixture? = nil
        var extra: [Fixture] = []
        let instruction: String
        let shape: String
        let colours: [String]
        var expectsPicture = true
        var question = PictureProbe.shapeQuestion
    }

    static let circle = Fixture(file: "img_probe_kreis.jpg", shape: "kreis", colour: "rot",
                                canvas: CGSize(width: 900, height: 1400),
                                background: UIColor(white: 0.98, alpha: 1),
                                object: UIColor(red: 0.82, green: 0.13, blue: 0.15, alpha: 1),
                                kind: .ellipse)
    static let square = Fixture(file: "img_probe_quadrat.jpg", shape: "quadrat", colour: "blau",
                                canvas: CGSize(width: 1400, height: 900),
                                background: UIColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1),
                                object: UIColor(red: 0.12, green: 0.35, blue: 0.78, alpha: 1),
                                kind: .rectangle)
    static let triangle = Fixture(file: "img_probe_dreieck.jpg", shape: "dreieck", colour: "grun",
                                  canvas: CGSize(width: 1100, height: 1100),
                                  background: UIColor(red: 0.67, green: 0.84, blue: 0.98, alpha: 1),
                                  object: UIColor(red: 0.11, green: 0.59, blue: 0.28, alpha: 1),
                                  kind: .triangle)
    static let star = Fixture(file: "img_probe_stern.jpg", shape: "stern", colour: "gelb",
                              canvas: CGSize(width: 1000, height: 1300),
                              background: UIColor(red: 0.06, green: 0.25, blue: 0.17, alpha: 1),
                              object: UIColor(red: 0.94, green: 0.78, blue: 0.12, alpha: 1),
                              kind: .star)
    static let rectangle = Fixture(file: "img_probe_rechteck.jpg", shape: "rechteck", colour: "schwarz",
                                   canvas: CGSize(width: 1300, height: 800),
                                   background: UIColor(red: 0.98, green: 0.88, blue: 0.67, alpha: 1),
                                   object: UIColor(white: 0.1, alpha: 1),
                                   kind: .roundedRectangle)

    static let fixtures = [circle, square, triangle, star]
    static var all: [Fixture] { fixtures + [rectangle] }

    static func materialise(in media: MediaStore) {
        for fixture in all where media.data(named: fixture.file) == nil {
            if let data = fixture.data() {
                try? data.write(to: media.paths.image(fixture.file))
            }
        }
    }

    static let shapeQuestion = "Sage in genau einem Satz: Welche Hauptform siehst du, und welche Farbe hat sie?"
    static let sizeQuestion = "Sage in genau einem Satz: Welche Hauptform siehst du, welche Farbe hat sie, "
        + "wie groß füllt sie das Bild (klein, mittel oder fast vollständig), und wie viele verschiedene "
        + "Hauptformen sind es insgesamt?"
    static let objectCountQuestion = "Antworte mit genau einem Wort (eins, zwei oder drei): Wie viele "
        + "verschiedene Hauptformen (Objekte) sind in diesem Bild zu sehen?"
    static let backgroundQuestion = "Sage in genau einem Satz: Welche Hauptform siehst du in welcher Farbe, "
        + "und welche Farbe hat der Hintergrund?"

    static let cases: [TestCase] = [
        TestCase(name: "farbe_zweites_auf_erstes",
                 instruction: "Übertrage die Farbe aus dem zweiten Foto auf das erste Foto.",
                 shape: "kreis", colours: ["blau"]),
        TestCase(name: "farbe_viertes_auf_erstes",
                 instruction: "Nimm die Farbe vom vierten Bild und male das erste Bild damit an.",
                 shape: "kreis", colours: ["gelb"]),
        TestCase(name: "farbe_erstes_auf_drittes",
                 instruction: "Gib dem dritten Foto die Farbe des ersten Fotos.",
                 shape: "dreieck", colours: ["rot"]),
        TestCase(name: "frisch_mitgeschickt_auf_erstes", attached: square,
                 instruction: "Übertrage die Farbe von dem Foto, das ich dir gerade mitschicke, "
                 + "auf das erste Foto im Chat.",
                 shape: "kreis", colours: ["blau"]),
        TestCase(name: "groesse_viertes_wie_erstes",
                 instruction: "Mache den Gegenstand aus dem vierten Foto genau so groß wie den "
                 + "Gegenstand aus dem ersten Foto.",
                 shape: "stern", colours: ["gelb"], question: sizeQuestion),
        TestCase(name: "hintergrund_zweites_auf_viertes",
                 instruction: "Nimm den Hintergrund aus dem zweiten Foto und gib das vierte Foto damit wieder.",
                 shape: "stern", colours: ["grau", "schwarz", "dunkel"], question: backgroundQuestion),
        TestCase(name: "nur_frage_kein_bild",
                 instruction: "Was ist auf dem ersten Foto zu sehen?",
                 shape: "kreis", colours: ["rot"], expectsPicture: false),
        TestCase(name: "ueberlauf_kappe_haelt_erstes_und_neueste", extra: [rectangle],
                 instruction: "Ändere die Farbe des ersten Fotos in die Farbe des dritten Fotos.",
                 shape: "kreis", colours: ["grun"]),
    ]

    static func folded(_ text: String) -> String { CalendarChoice.normalize(text) }

    static func foreignShapes(except shape: String) -> [String] {
        all.map(\.shape).filter { $0 != shape }
    }

    static func meanRGB(of image: UIImage) -> (Int, Int, Int) {
        let side = 24
        guard let cg = image.cgImage else { return (0, 0, 0) }
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8,
                                     bytesPerRow: side * 4,
                                     space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return (0, 0, 0)
        }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        var red = 0, green = 0, blue = 0
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            red += Int(pixels[offset])
            green += Int(pixels[offset + 1])
            blue += Int(pixels[offset + 2])
        }
        let count = side * side
        return (red / count, green / count, blue / count)
    }

    static func rgbText(_ image: UIImage) -> String {
        let rgb = meanRGB(of: image)
        return "\(Int(image.size.width))x\(Int(image.size.height)) rgb(\(rgb.0),\(rgb.1),\(rgb.2))"
    }
}
#endif
