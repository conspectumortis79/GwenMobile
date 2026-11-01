@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import EventKit
import UIKit

extension ChatView {
    var lastAnswer: ChatMessage? {
        store.current?.messages.last(where: { $0.role == .assistant })
    }

    @MainActor @discardableResult func ask(_ question: String, fresh: Bool = false) async -> ChatMessage? {
        if fresh { store.newConversation() }
        input = question
        await send()
        return lastAnswer
    }

    func runSweep() async {
        await withScreenAwake {
            let report = SweepReport(file: "flow_sweep.txt")
            let baseURL = settings.baseURL
            let key = settings.apiKey
            report.add("KONFIG", "schluessel=\(settings.isConfigured) chat=\(settings.chatModel) vision=\(settings.visionModel) bild=\(settings.imageModel) sprache=\(L.lang.rawValue) basis=\(baseURL)")

            do {
                let models = try await QwenAPI.fetchModels(baseURL: baseURL, key: key)
                report.add("MODELLE", "anzahl=\(models.count) erste=\(models.prefix(3).joined(separator: ","))")
            } catch { report.addFailure("MODELLE", error) }

            do {
                let answer = try await askOnce("Was ist die Hauptstadt von Frankreich?")
                report.add("CHAT_WISSEN", "zeichen=\(answer.count) suchToken=\(answer.contains(SearchMarker.token)) anfang=\(TextLine.oneLine(answer, limit: 70))")
            } catch { report.addFailure("CHAT_WISSEN", error) }

            do {
                let answer = try await askOnce("Aktuelle Nachrichten")
                report.add("CHAT_SUCHHINWEIS", "suchToken=\(answer.contains(SearchMarker.token)) anfang=\(TextLine.oneLine(answer, limit: 70))")
            } catch { report.addFailure("CHAT_SUCHHINWEIS", error) }

            for lauf in 1...ProbeRounds.maximum {
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
                                                                 hits: hits,
                                                                 thinking: settings.thinkingOffDirective(
                                                                    for: settings.chatModel))
                        let answer = try await ChatRunner.shared.run(req) { _ in }
                        report.add("WEBANTWORT\(lauf)", "zeichen=\(answer.count) anfang=\(TextLine.oneLine(answer, limit: 70))")
                    }
                } catch { report.addFailure("WEBPFAD\(lauf)", error) }
                try? await Task.sleep(for: .seconds(2))
            }

            let uiAnswer = await ask("Aktuelle Nachrichten", fresh: true)
            report.add("UI_SUCHE", "quellen=\(uiAnswer?.sources?.count ?? -1) zeichen=\(uiAnswer?.text.count ?? -1) anfang=\(TextLine.oneLine(uiAnswer?.text ?? "", limit: 70))")
            report.add("UI_SUCHE_KAPSEL", "danach=\(webStatus ?? "nil")")
            let uiPlain = await ask("Was ist die Hauptstadt von Frankreich?", fresh: true)
            report.add("UI_WISSEN", "quellen=\(uiPlain?.sources?.count ?? -1) zeichen=\(uiPlain?.text.count ?? -1) anfang=\(TextLine.oneLine(uiPlain?.text ?? "", limit: 70))")

            do {
                let followUp = [ChatMessage(role: .user, text: "Was sind die Hauptursachen der Klimaerwärmung?"),
                                ChatMessage(role: .assistant,
                                            text: "Die Hauptursachen sind die Verbrennung von Kohle, Öl und Gas, Industrie, Landwirtschaft und Abholzung."),
                                ChatMessage(role: .user, text: "und in Deutschland?")]
                for lauf in 1...ProbeRounds.maximum {
                    let raw = try await QwenAPI.resolveQuery(baseURL: baseURL, key: key,
                                                             model: settings.chatModel, history: followUp,
                                                             thinking: settings.thinkingOffDirective(
                                                                for: settings.chatModel))
                    let query = raw ?? ""
                    report.add("KONTEXT_FRAGE\(lauf)",
                               "nutzbar=\(FollowUpResolver.isUsable(query, insteadOf: "und in Deutschland?")) abfrage=\(query)")
                }
            } catch { report.addFailure("KONTEXT_FRAGE", error) }

            let role1 = await ask("Wie viele Einwohner hat Deutschland in den letzten Jahren jeweils gehabt?", fresh: true)
            report.add("KONTEXT_ROLLE1", "zeichen=\(role1?.text.count ?? -1) quellen=\(role1?.sources?.count ?? -1) anfang=\(TextLine.oneLine(role1?.text ?? "", limit: 70))")

            await ask("Was ist die Hauptstadt von Frankreich?", fresh: true)
            let shortFollow = await ask("Und in Österreich?")
            report.add("KONTEXT_KURZFRAGE", "zeichen=\(shortFollow?.text.count ?? -1) quellen=\(shortFollow?.sources?.count ?? -1) anfang=\(TextLine.oneLine(shortFollow?.text ?? "", limit: 70))")

            let status = EKEventStore.authorizationStatus(for: .event)
            report.add("KALENDER_RECHT", "status=\(status.rawValue)")
            report.add("KALENDER_KONTEXT", "zeichen=\(CalendarService.upcomingContext().count)")
            do {
                if let plan = try await QwenAPI.calendarPlan(baseURL: baseURL, key: key, model: settings.chatModel,
                                                            instruction: "Leg bitte morgen um 14 Uhr einen Zahnarzttermin für eine Stunde an",
                                                            calendars: CalendarService.calendarsContext(),
                                                            thinking: settings.thinkingOffDirective(
                                                                for: settings.chatModel)) {
                    report.add("KALENDER_PLAN", "aktion=\(plan.action) titel=\(plan.title ?? "-") start=\(plan.start ?? "-") end=\(plan.end ?? "-") alerten=\(plan.alerts.map { String(describing: $0) } ?? "-") kalender=\(plan.calendar ?? "-")")
                } else {
                    report.add("KALENDER_PLAN", "keinPlan")
                }
            } catch { report.addFailure("KALENDER_PLAN", error) }

            let stored = store.media.data(named: flowTestBigImage)
            report.add("SANDBOX_BILD", "vorhanden=\(stored != nil) bytes=\(stored?.count ?? -1)")

            if let stored, let image = await decodedThumbnail(stored) {
                store.newConversation()
                pendingImages = [PendingPicture(image: image, file: flowTestBigImage)]
                input = PictureProbe.lighten
                let beforeEdit = store.current?.messages.count ?? 0
                await send()
                let edited = assistantMessage(afterIndex: beforeEdit)
                report.add("BILDBEARBEITUNG", "ausgabebilder=\(edited?.outImages?.count ?? -1) antwortzeichen=\(edited?.text.count ?? -1)")
            }

            if let backend = settings.descriptor.imageBackend {
                do {
                    let pictures = try await backend.generate(baseURL: baseURL, key: key, model: settings.imageModel,
                                                              prompt: "Eine rote Tasse auf einem Tisch",
                                                              inputImages: [], isEdit: false)
                    report.add("BILDERGENERIERUNG", "bilder=\(pictures.count) modell=\(settings.imageModel)")
                } catch { report.addFailure("BILDERGENERIERUNG", error) }
            } else {
                report.add("BILDERGENERIERUNG", "kein bildmodell beim anbieter \(settings.provider.rawValue)")
            }

            let speechRecognizer = SystemSpeechRecognizer(locale: settings.language.locale)
            report.add("SPRACHE_IOS", "erkennung_status=\(SystemSpeechRecognizer.authorizationStatus.rawValue) "
                       + "verfuegbar=\(speechRecognizer.isAvailable) "
                       + "stimme=\(VoiceCatalog.defaultVoiceName(for: settings.language))")

            let paths = StoragePaths()
            let reloaded = ChatStore(media: MediaStore(paths: paths), paths: paths)
            report.add("PERSISTENZ", "unterhaltungenNeuGeladen=\(reloaded.conversations.count) nachRunden=\(store.conversations.count)")
            report.add("OBERFLAECHE", "unterhaltungen=\(store.conversations.count) nachrichten=\(store.conversations.reduce(0) { $0 + $1.messages.count })")

            flowLog.info("SWEEP bericht geschrieben")
        }
    }

    private func askOnce(_ text: String) async throws -> String {
        let req = try QwenAPI.makeRequest(baseURL: settings.baseURL, key: settings.apiKey,
                                          model: settings.chatModel,
                                          messages: [ChatMessage(role: .user, text: text)], imageData: [],
                                          thinking: settings.thinkingOffDirective(for: settings.chatModel))
        return try await ChatRunner.shared.run(req) { _ in }
    }

    private func rememberedFiles(_ messages: [ChatMessage]) -> [String] {
        ConversationMemory.turn(from: messages) { store.media.data(for: $0) }.pictureFiles
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
        await withScreenAwake {
            let report = SweepReport(file: "model_caps_probe.txt")
            let loaded = settings.availableModels.isEmpty
                ? (try? await QwenAPI.fetchModels(baseURL: settings.baseURL, key: settings.apiKey)) ?? []
                : settings.availableModels
            let textModels = ModelFilter.textCandidates(loaded)
            report.add("SONDE_LISTE", "gesamt=\(loaded.count) text=\(textModels.count) chat=\(settings.chatModel) vision=\(settings.visionModel) gewaehlt=\(settings.chatThinkingLevel.rawValue)")
            let caps = await CapabilityProber.dashScope.discover(baseURL: settings.baseURL, key: settings.apiKey,
                                                        models: textModels)
            let stored = settings.profile.modelCaps.merging(caps) { _, new in new }
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
            flowLog.info("CAPSPROBE bericht geschrieben")
        }
    }

    private static func directiveSummary(_ directive: ThinkingDirective) -> String {
        guard directive.sendsAnything else { return "nichts" }
        return directive.bodyEntries.map { key, value in "\(key)=\(value)" }.sorted().joined(separator: ",")
    }

    func runAirDropProbe() async {
        await withScreenAwake {
            let report = SweepReport(file: "airdrop_probe.txt")
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
                return
            }
            let bytes = (try? Data(contentsOf: url))?.count ?? -1
            report.add("AIRDROP_DATEI", "name=\(url.lastPathComponent) endung=\(url.pathExtension) bytes=\(bytes)")
            do {
                try Presenter.share(url: url)
            } catch {
                report.addFailure("AIRDROP_FENSTER", error)
                return
            }
            var gefunden: UIActivityViewController?
            for _ in 0..<50 {
                try? await Task.sleep(for: .milliseconds(200))
                if let sheet = Presenter.topViewController as? UIActivityViewController { gefunden = sheet; break }
            }
            guard let sheet = gefunden else {
                report.add("AIRDROP_BEOBACHTUNG", "keinSheet")
                return
            }
            let events = ShareProbeEvents()
            let observer = ShareFlowObserver(sheet: sheet, events: events)
            guard let session = Presenter.lastShareSession else {
                report.add("AIRDROP_SESSION", "keine")
                sheet.dismiss(animated: true)
                _ = await ProbeWait.until(3) { observer.sheetIsGone }
                report.add("AIRDROP_ENDE", "chatSichtbarWieder=\(observer.sheetIsGone)")
                return
            }
            let source = session.itemSource(for: url)
            _ = source.activityViewController(sheet, itemForActivityType: .mail)
            try? await Task.sleep(for: .milliseconds(300))
            observer.tick()
            let remainedOpen = !observer.sheetIsGone
            report.add("AIRDROP_ANDERE_AKTIVITAET", "typ=mail offen=\(remainedOpen)")
            let handedURL = (source.activityViewController(sheet, itemForActivityType: .airDrop) as? URL) == url
            report.add("AIRDROP_CALLBACK", "typ=airDrop datei=\(handedURL) quelle=itemSource")
            let closed = await ProbeWait.until(3) { observer.sheetIsGone }
            observer.tick()
            report.add("AIRDROP_HANDOVER", "simuliert=true typ=airDrop session_da=true "
                       + "callback=\(handedURL) sheet_weg=\(closed) ok=\(remainedOpen && handedURL && closed)")
            Presenter.lastShareSession = nil
            if !closed {
                sheet.dismiss(animated: true)
                _ = await ProbeWait.until(3) { observer.sheetIsGone }
            }
            report.add("AIRDROP_BEOBACHTUNG", "ereignisse=\(events.all.count)")
            for line in events.all { report.add("BEOB", line) }
            report.add("AIRDROP_ENDE", "chatSichtbarWieder=\(observer.sheetIsGone)")
            flowLog.info("AIRDROPPROBE bericht geschrieben")
        }
    }

    func runCodeGuardProbe() async {
        await withScreenAwake {
            let report = SweepReport(file: "code_guard.txt")
            let answer = await ask("Programmiere mir Tetris als eine einzige HTML-Datei, die ich im Browser "
                                   + "mit Tasten spielen kann", fresh: true)
            let text = answer?.text ?? ""
            let blocks = CodeText.blocks(in: text)
            report.add("ANTWORT", "zeichen=\(text.count) bilder=\(answer?.outImages?.count ?? 0) "
                       + "codeblocks=\(blocks.count) zeilen=\(blocks.first?.lineCount ?? -1) "
                       + "sprache=\(blocks.first?.language.rawValue ?? "-") "
                       + "zaeune=\(text.components(separatedBy: CodeText.fence).count - 1) "
                       + "anfang=\(TextLine.oneLine(text, limit: 70))")
            let pieces = CodeText.segments(from: text)
            report.add("SEGMENTE", "anteile=\(pieces.count) text=\(pieces.filter { $0.prose != nil }.count) "
                       + "code=\(pieces.filter { $0.code != nil }.count)")
            guard let block = blocks.first else {
                flowLog.info("CODEGUARD bericht geschrieben")
                return
            }
            do {
                let url = try CodeFileExporter().write(block, question: "Tetris", date: Date())
                let size = try Data(contentsOf: url).count
                let stored = try String(contentsOf: url, encoding: .utf8)
                let lower = stored.lowercased()
                report.add("DATEI", "name=\(url.lastPathComponent) bytes=\(size) "
                           + "zeilen=\(block.lineCount) sprache=\(block.language.rawValue) "
                           + "vollstaendig=\(lower.contains("<!doctype") && lower.contains("</html>")) "
                           + "zaeuneInDerDatei=\(stored.contains(CodeText.fence))")
                try? FileManager.default.removeItem(at: url)
            } catch { report.addFailure("DATEI", error) }
            flowLog.info("CODEGUARD bericht geschrieben")
        }
    }

    func runExportProbe() async {
        await withScreenAwake {
            let report = SweepReport(file: "export_probe.txt")
            store.newConversation()
            input = "Was ist die Hauptstadt von Frankreich? Nenne zwei Meilensteine mit Quellen."
            await send()
            let messages = store.current?.messages ?? []
            guard let answer = messages.last(where: { $0.role == .assistant }) else {
                report.add("EXPORT_DATEI", "keineAntwort")
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
            flowLog.info("EXPORTPROBE bericht geschrieben")
        }
    }

    func runSearchOnceProbe() async {
        await withScreenAwake {
            let report = SweepReport(file: "search_once.txt")
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
            let answer = await ask("Wie viele Arbeitslose gab es in Deutschland in den letzten zwei Jahren?", fresh: true)
            report.add("SUCHE_ONCE", "zeichen=\(answer?.text.count ?? -1) quellen=\(answer?.sources?.count ?? -1) "
                       + "nachrichten=\(store.current?.messages.count ?? -1) kapsel=\(webStatus ?? "nil")")
            flowLog.info("SEARCHONCE bericht geschrieben")
        }
    }

    func runPictureSweep() async {
        await withScreenAwake {
            let report = SweepReport(file: PictureProbe.report)
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
                return
            }

            store.newConversation()
            let chatID = store.current?.id
            for fixture in PictureProbe.fixtures { postPicture(fixture) }
            let baseline = store.current?.messages ?? []
            let remembered = rememberedFiles(baseline)
            report.add("BASELINE", "nachrichten=\(baseline.count) erinnert=\(remembered.count) "
                       + "reihenfolge=\(remembered.joined(separator: ","))")

            for testCase in ProbeRounds.capped(PictureProbe.cases) {
                restore(messages: baseline, into: chatID)
                for fixture in testCase.extra { postPicture(fixture) }
                let history = store.current?.messages ?? []
                report.add("AUSWAHL_\(testCase.name)",
                           "erinnert=\(rememberedFiles(history).joined(separator: ",")) "
                           + "anhang=\(testCase.attached?.file ?? "-") kap=\(ConversationMemory.maxPictures)")
                pendingImages = []
                if let attached = testCase.attached,
                   let picture = store.media.decodedDisplayImage(named: attached.file) {
                    pendingImages = [PendingPicture(image: picture, file: attached.file)]
                }
                input = testCase.instruction
                await send()
                let reply = store.current?.messages.last ?? ChatMessage(role: .assistant, text: "keine antwort")
                let file = (reply.outImages ?? []).first?.file ?? ""
                let folded = PictureProbe.folded(reply.text)
                let colourMatched = PictureProbe.matchesColour(testCase.colours, in: folded)
                if !testCase.expectsPicture {
                    report.add("FALL_\(testCase.name)", "bild_erwartet=nein out=\(file.isEmpty ? "none" : file) "
                               + "form_ok=\(folded.contains(testCase.shape)) farbe_ok=\(colourMatched) "
                               + "text=\(TextLine.oneLine(reply.text, limit: 70))")
                    continue
                }
                let picture = file.isEmpty ? nil : store.media.exportImage(named: file)
                if file.isEmpty {
                    report.add("FALL_\(testCase.name)_OHNE_BILD",
                               "runden=1 antwort=\(TextLine.oneLine(reply.text, limit: 150)) "
                                   + "meldungen=\(probeAlerts.count)")
                }
                let shape = await describePicture(file: file, question: testCase.question)
                let count = await describePicture(file: file, question: PictureProbe.objectCountQuestion)
                let look = shape + " " + count
                let seen = PictureProbe.folded(look)
                let foreign = PictureProbe.foreignShapes(except: testCase.shape)
                report.add("FALL_\(testCase.name)",
                           "datei=\(file) gemessen=\(picture.map { PictureProbe.rgbText($0) } ?? "-") "
                               + "form_erwartet=\(testCase.shape) form_ok=\(seen.contains(testCase.shape)) "
                               + "farben_erwartet=\(testCase.colours.joined(separator: "|")) "
                               + "farbe_ok=\(PictureProbe.matchesColour(testCase.colours, in: seen)) "
                               + "fremde_formen_ok=\(!foreign.contains { seen.contains($0) }) "
                               + "sicht=\(String(look.prefix(150)).replacingOccurrences(of: "\n", with: " "))")
            }
            flowLog.info("PICTURESWEEP bericht geschrieben")
        }
    }

    private func postPicture(_ fixture: PictureProbe.Fixture) {
        guard let chatID = store.currentID, store.media.data(named: fixture.file) != nil else { return }
        store.appendMessage(ChatMessage(role: .user, text: "Vorlage \(fixture.shape)",
                                        images: [Attachment(file: fixture.file)]), to: chatID)
    }

    private func restore(messages: [ChatMessage], into id: UUID?) {
        guard let index = store.conversations.firstIndex(where: { $0.id == id }) else { return }
        store.conversations[index].messages = messages
    }

    private func describePicture(file: String, question: String) async -> String {
        guard let data = store.media.data(named: file) else { return "kein bild geladen" }
        do {
            let model = settings.answeringModel(hasPictures: true)
            let req = try QwenAPI.makeRequest(baseURL: settings.baseURL, key: settings.apiKey,
                                              model: model,
                                              messages: [ChatMessage(role: .user, text: question,
                                                                     images: [Attachment(file: file)])],
                                              imageData: [data],
                                              thinking: settings.thinkingOffDirective(for: model))
            return try await ChatRunner.shared.run(req) { _ in }
        } catch {
            return "FEHLER " + error.localizedDescription
        }
    }

}
#endif
