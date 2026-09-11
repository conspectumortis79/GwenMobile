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
            try Presenter.share(url: url, closesOn: [.airDrop])
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
#endif
