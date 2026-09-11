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
        store.newConversation()
        input = "Was ist die Hauptstadt von Frankreich?"
        await send()
        let uiPlain = store.current?.messages.last(where: { $0.role == .assistant })
        report.add("UI_WISSEN", "quellen=\(uiPlain?.sources?.count ?? -1) zeichen=\(uiPlain?.text.count ?? -1) anfang=\(prefix(uiPlain?.text ?? ""))")

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

    private func prefix(_ text: String) -> String {
        String(text.prefix(70)).replacingOccurrences(of: "\n", with: " ")
    }
}
#endif
