@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import UIKit

@MainActor
enum DebugPictureSearchProbe {
    private enum Wish: String {
        case pictures = "bildersuche"
        case create = "bild erzeugen"
        case edit = "bild bearbeiten"
        case chat = "nur chat"
        case other = "anderes"

        init(route: SendRoute) {
            switch route {
            case .pictureSearch: self = .pictures
            case .imageCreate: self = .create
            case .imageEdit: self = .edit
            case .chat: self = .chat
            default: self = .other
            }
        }
    }

    static func flip(_ view: ChatView) async {
        let report = SweepReport(file: "picture_flip.txt")
        let model = view.settings.chatModel
        let thinking = view.settings.thinkingOffDirective(for: model)
        let cases: [(String, SendContext)] = [
            ("hat jemand fotos von dem unfall auf der a3", SendContext()),
            ("male cary elwes als pirat", SendContext()),
            ("wie viel kostet das hier bei mir im Laden?", SendContext(attachedImage: true)),
            ("mache das bild etwas heller", SendContext(attachedImage: true)),
        ]
        report.add("BUDGET", "max_tokens=\(ToolRouter.maxTokens) modell=\(model) "
                   + "denkabsicht=\(String(describing: thinking.intent))")
        for (sentence, context) in ProbeRounds.capped(cases) {
            var namen: [String] = []
            for _ in 1...ProbeRounds.maximum {
                let name = await attempt(view, sentence: sentence, context: context,
                                     model: model, thinking: thinking)
                namen.append(name)
            }
            let gruppen = Dictionary(grouping: namen, by: { $0 }).map { "\($0.key)x\($0.value.count)" }
                .sorted().joined(separator: ",")
            report.add("ROHVERTEILUNG_\(TextLine.oneLine(sentence, limit: 28))",
                       "antworten=\(gruppen)")
            var entscheide: [String] = []
            for _ in 1...8 {
                let decision = await ToolRouter.decide(RouterAsk(baseURL: view.settings.baseURL,
                                                                 key: view.settings.apiKey, model: model,
                                                                 text: sentence, context: context, history: [],
                                                                 picture: nil, thinking: thinking))
                entscheide.append(decision.map { Wish(route: $0.route).rawValue } ?? "keine_entscheidung")
            }
            let entscheidungen = Dictionary(grouping: entscheide, by: { $0 })
                .map { "\($0.key)x\($0.value.count)" }.sorted().joined(separator: ",")
            report.add("APP_\(TextLine.oneLine(sentence, limit: 28))", "entscheidungen=\(entscheidungen)")
        }
        flowLog.info("WERKZEUGFLIP fertig")
    }

    private static func attempt(_ view: ChatView, sentence: String, context: SendContext,
                                model: String, thinking: ThinkingDirective) async -> String {
        let system = ToolRouter.systemBlock(now: SystemPrompt.currentDate(), context: context, transcript: "")
        let attachable = context.attachedImage || context.rememberedImage
        do {
            let request = try ToolRouter.request(baseURL: view.settings.baseURL, key: view.settings.apiKey,
                                                 model: model, text: sentence, system: system,
                                                 attachable: attachable, thinking: thinking)
            let data = try await HTTP.jsonData(request)
            return rawName(data)
        } catch {
            return "fehler"
        }
    }

    private static func rawName(_ data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let calls = message["tool_calls"] as? [[String: Any]],
              let name = ((calls.first?["function"] as? [String: Any])?["name"] as? String)
        else { return "kein_werkzeugbericht(ende=\(finishOf(data)),text=\(textLength(data)))" }
        return name
    }

    private static func finishOf(_ data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]]
        else { return "-" }
        return choices.first?["finish_reason"] as? String ?? "-"
    }

    private static func textLength(_ data: Data) -> Int {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any]
        else { return -1 }
        return ((message["content"] as? String) ?? "").count
    }

    static func honesty(_ view: ChatView) async {
        let report = SweepReport(file: "picture_honesty.txt")
        let fixtures = PictureProbe.fixtures
        let missing = fixtures.filter { view.store.media.data(named: $0.file) == nil }
        report.add("VORLAGEN", "fehlend=\(missing.isEmpty ? "keine" : missing.map(\.file).joined(separator: ","))")
        guard missing.isEmpty else {
            report.add("ABBRECH", "makefixtures zuerst laufen lassen")
            return
        }
        let sentences = PictureProbe.recolourAsks
            + ["Mache den Gegenstand aus dem gelben Stern genau so groß wie den aus dem roten Kreis."]
        for (round, sentence) in ProbeRounds.capped(sentences).enumerated() {
            view.store.newConversation()
            guard let chatID = view.store.currentID else { return }
            for fixture in fixtures {
                view.store.appendMessage(ChatMessage(role: .user, text: "Vorlage \(fixture.shape)",
                                                     images: [Attachment(file: fixture.file)]), to: chatID)
            }
            view.pendingImages = []
            view.input = sentence
            await view.send()
            let reply = view.lastAnswer
            let text = reply?.text ?? ""
            let folded = text.lowercased()
            let pictureCameBack = (reply?.outImages ?? []).isEmpty == false
            let denies = denialPhrases.contains { folded.contains($0) }
            let claims = !denies && claimPhrases.contains { folded.contains($0) }
            report.add("RUNDE_\(round)", "bild_gekommen=\(pictureCameBack) behauptet=\(claims) "
                       + "ehrlich=\(denies) zeichen=\(text.count) "
                       + "text=\(TextLine.oneLine(text, limit: 130))")
            report.add("RUNDE_\(round)_SATZ", TextLine.oneLine(sentence, limit: 90))
        }
        flowLog.info("BILDEHRLICHKEIT fertig")
    }

    private static let denialPhrases = ["nicht geändert", "unverändert", "nicht bearbeitet",
                                        "kein neues bild", "kann keine bilder", "kann ich keine",
                                        "not changed", "cannot change", "can't change", "no new picture",
                                        "nicht neu gefärbt", "konnte das bild nicht"]

    private static let claimPhrases = ["übertragen", "wurde die", "habe ich das bild", "jetzt hell",
                                       "heller gemacht", "angepasst", "geändert", "ich habe das bild",
                                       "transferred", "i changed", "i made", "recoloured", "neue farbe"]

    static func editContext(_ view: ChatView) async {
        let report = SweepReport(file: "picture_edit_context.txt")
        let sentences = PictureProbe.recolourAsks + [PictureProbe.starOntoCircle, PictureProbe.lighten]
        let history: [ChatMessage] = PictureProbe.fixtures.map { fixture in
            ChatMessage(role: .user, text: "Vorlage \(fixture.shape)",
                        images: [Attachment(file: fixture.file)])
        }
        let model = view.settings.chatModel
        let thinking = view.settings.thinkingOffDirective(for: model)
        for (index, sentence) in sentences.enumerated() {
            let alone = await ToolRouter.decide(RouterAsk(baseURL: view.settings.baseURL,
                                                           key: view.settings.apiKey,
                                                           model: model, text: sentence,
                                                           context: SendContext(),
                                                           history: [], thinking: thinking))
            let remembered = await ToolRouter.decide(RouterAsk(baseURL: view.settings.baseURL,
                                                               key: view.settings.apiKey,
                                                               model: model, text: sentence,
                                                               context: SendContext(rememberedImage: true),
                                                               history: history, thinking: thinking))
            report.add("SATZ_\(index)",
                       "ohne_kontext=\(Wish(route: alone?.route ?? .chat).rawValue) "
                           + "mit_erinnertem_bild=\(Wish(route: remembered?.route ?? .chat).rawValue) "
                           + "terms=\(TextLine.oneLine((remembered?.pictureInstruction ?? "-"), limit: 40)) "
                           + "satz=\(TextLine.oneLine(sentence, limit: 44))")
        }
        flowLog.info("BILDBEARBEITUNG kontext fertig")
    }

    static func editRoute(_ view: ChatView) async {
        let report = SweepReport(file: "picture_edit_route.txt")
        let fixtures = PictureProbe.fixtures
        let pictures = fixtures.map { fixture in (fixture.shape, view.store.media.data(named: fixture.file)) }
        let missing = fixtures.filter { view.store.media.data(named: $0.file) == nil }
        report.add("VORLAGEN", "fehlend=\(missing.isEmpty ? "keine" : missing.map(\.file).joined(separator: ","))")
        guard missing.isEmpty, let first = pictures.first, let last = pictures.last else {
            report.add("ABBRUCH", "makefixtures zuerst laufen lassen")
            return
        }
        let templates = fixtures.map { fixture in
            ChatMessage(role: .user, text: "Vorlage \(fixture.shape)", images: [Attachment(file: fixture.file)])
        }
        let variants: [(String, Data?)] = [("letztes_bild_\(last.0)", last.1), ("ohne_bild", nil),
                                           ("erstes_bild_\(first.0)", first.1)]
        let sentences = PictureProbe.recolourAsks + [PictureProbe.starOntoCircle, PictureProbe.lighten]
        for (index, sentence) in sentences.enumerated() {
            report.add("SATZ_\(index)", TextLine.oneLine(sentence, limit: 90))
            for (label, picture) in variants {
                await routeRounds(view, report: report, key: "SATZ_\(index)_\(label)", sentence: sentence,
                                  templates: templates, picture: picture)
            }
        }
        for (index, sentence) in editRouteControls.enumerated() {
            report.add("KONTROLLE_\(index)", TextLine.oneLine(sentence, limit: 90))
            await routeRounds(view, report: report, key: "KONTROLLE_\(index)", sentence: sentence,
                              templates: templates, picture: last.1)
        }
        flowLog.info("BILDROUTE fertig")
    }

    private static let editRouteControls = ["Was ist auf dem roten Kreis zu sehen?",
                                            "Welche Farbe hat das blaue Quadrat genau?",
                                            "Zeichne ein neues Bild mit einem lila Sechseck.",
                                            "Zeig mir Fotos von echten Seesternen im Meer.",
                                            "Mach das grüne Dreieck schwarz-weiß.",
                                            "Wo kann ich so einen gelben Stern günstig kaufen?"]

    private static func routeRounds(_ view: ChatView, report: SweepReport, key: String, sentence: String,
                                    templates: [ChatMessage], picture: Data?) async {
        let remembered = templates.compactMap { template in
            template.images.first.flatMap { view.store.media.data(named: $0.file) }
        }
        let extra = picture.map { seen in remembered.filter { $0 != seen } } ?? remembered
        let history = templates + [ChatMessage(role: .user, text: sentence)]
        for round in 1...3 {
            let ask = await view.routerAsk(sentence, context: SendContext(rememberedImage: true),
                                           history: history, needsVision: true, picture: picture,
                                           extraPictures: extra)
            report.add("\(key)_\(round)", await wholeCalls(ask))
        }
    }

    private static func wholeCalls(_ ask: RouterAsk) async -> String {
        let system = ToolRouter.systemBlock(now: SystemPrompt.currentMoment(), context: ask.context,
                                            transcript: ConversationTranscript.withoutTheNewestQuestion(
                                                from: ask.history),
                                            catalog: ask.catalog, eraseHistoryWord: ask.eraseHistoryWord,
                                            document: ask.document, watchCatalog: ask.watchCatalog)
        let started = ContinuousClock.now
        do {
            let req = try ToolRouter.request(baseURL: ask.baseURL, key: ask.key, model: ask.model, text: ask.text,
                                             system: system,
                                             attachable: !ask.compact
                                                 && (ask.context.attachedImage || ask.context.rememberedImage),
                                             translatesOnDevice: !ask.context.textNeedsTheModel,
                                             pictures: ask.allPictures, parallel: true,
                                             compact: ask.compact, thinking: ask.thinking)
            let data = try await HTTP.jsonData(req)
            let ms = msOf(started.duration(to: .now))
            let calls = ToolRouter.toolCalls(from: data)
            guard !calls.isEmpty else { return "kein_call \(ToolRouter.answerShape(of: data)) ms=\(ms)" }
            return calls.map { "\($0.name) \(TextLine.oneLine($0.arguments, limit: 150))" }
                .joined(separator: " | ") + " ms=\(ms)"
        } catch {
            return "fehler=\(TextLine.oneLine(error.localizedDescription, limit: 120))"
        }
    }

    static func pictureProbe() async {
        let report = SweepReport(file: "picture_probe.txt")
        let queries = ["Cary Elwes",
                       "aurora borealis",
                       "denkmal für die ermordeten juden europas"]
        let search = BingPictureSearch()
        var pool: [PictureHit] = []
        for query in ProbeRounds.capped(queries) {
            let started = ContinuousClock.now
            do {
                let hits = try await search.pictures(for: query, offset: 1)
                let secure = hits.filter { $0.thumbURL.hasPrefix("https://") }.count
                let hosts = Set(hits.compactMap { URL(string: $0.thumbURL)?.host }).count
                let pages = Set(hits.map(\.domain)).count
                let titled = hits.filter { !$0.title.isEmpty }.count
                report.add("SUCHE", "abfrage=\(TextLine.oneLine(query, limit: 40)) treffer=\(hits.count) "
                           + "https=\(secure) bildhosts=\(hosts) quellseiten=\(pages) titel=\(titled) "
                           + "ms=\(msOf(started.duration(to: .now)))")
                if pool.isEmpty { pool = hits }
            } catch {
                report.add("SUCHE", "abfrage=\(TextLine.oneLine(query, limit: 40)) FEHLER "
                           + "\(error.localizedDescription.prefix(80))")
            }
        }
        let second = try? await search.pictures(for: queries[0], offset: ImagePolicy.galleryPageSpan + 1)
        let overlap = Set(pool.map(\.thumbURL)).intersection(Set((second ?? []).map(\.thumbURL))).count
        report.add("ZWEITE_SEITE", "treffer=\(second?.count ?? -1) wiederverwendet=\(overlap)")
        await storeRound(Array(pool.prefix(4)), report: report)
        report.add("POLITIK", "filter=\(BingPictureSearch.photoFilter) seitenlänge=\(ImagePolicy.galleryPageSpan) "
                   + "vorrat=\(ImagePolicy.galleryMaxStored) kacheln_zuvor=\(ImagePolicy.galleryInitialItems) "
                   + "px=\(ImagePolicy.galleryThumbPixel) fenster=\(ImagePolicy.galleryDownloadWindow)")
        flowLog.info("BILDERSUCHE probe fertig")
    }

    private static func storeRound(_ hits: [PictureHit], report: SweepReport) async {
        guard !hits.isEmpty else {
            report.add("LADEN", "keine treffer — übersprungen")
            return
        }
        let paths = StoragePaths(documents: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true))
        let media = MediaStore(paths: paths)
        media.prepareDirectories()
        let downloaded = await downloads(hits)
        let stored = PictureSearchFlow.store(downloaded, over: hits, media: media)
        report.add("LADEN", "versuche=\(hits.count) geladen=\(downloaded.count) gespeichert=\(stored.count) "
                   + "dateien_stimmen=\(Set(media.fileNames()) == Set(stored.map(\.file)))")
        for picture in stored.prefix(3) {
            let bytes = media.data(named: picture.file)?.count ?? -1
            let side = await Task.detached(priority: .userInitiated) {
                MediaStore.thumbnail(media.data(named: picture.file) ?? Data(),
                                     maxPixel: ImagePolicy.viewerMaxPixel)?.size ?? .zero
            }.value
            report.add("KACHEL", "domain=\(picture.domain) byte=\(bytes) "
                       + "px=\(Int(side.width))x\(Int(side.height)) "
                       + "titel=\(TextLine.oneLine(picture.title, limit: 44))")
        }
        let gallery = PictureGallery(query: "probe", pictures: stored,
                                    shown: ImagePolicy.galleryInitialItems,
                                    nextOffset: ImagePolicy.galleryPageSpan + 1, exhausted: false)
        report.add("GALERIE", "sichtbar=\(gallery.visiblePictures.count) versteckt=\(gallery.hiddenCount) "
                   + "mehr_knopf=\(gallery.hiddenCount > 0 || !gallery.exhausted) quellen=\(gallery.chipSources.count) "
                   + "text=\(TextLine.oneLine(ChatView.galleryAnswer(gallery: gallery, failures: hits.count - stored.count), limit: 120))")
        media.discardStored(gallery.files)
        report.add("AUFRÄUMEN", "übrig=\(media.fileNames().count)")
    }

    private static func downloads(_ hits: [PictureHit]) async -> [(Int, Data)] {
        let fetch = HTTPPictureFetching()
        var done: [(Int, Data)] = []
        for (index, hit) in hits.enumerated() {
            guard let url = HTTPPictureFetching.secureURL(hit.thumbURL),
                  let bytes = try? await fetch.data(from: url) else { continue }
            done.append((index, bytes))
        }
        return done
    }

    static func routeGuard(_ view: ChatView) async {
        let report = SweepReport(file: "picture_guard.txt")
        let cases: [(text: String, attached: Bool, expected: Wish)] = [
            ("finde mir alle bilder von cary elwes", false, .pictures),
            ("zeig mir fotos vom nordlicht", false, .pictures),
            ("such mir bilder von der eifelturm eröffnung", false, .pictures),
            ("hat jemand fotos von dem unfall auf der a3", false, .pictures),
            ("finde mir fotos von der mona lisa", false, .pictures),
            ("male cary elwes als pirat", false, .create),
            ("erzeuge ein bild einer stadt bei nacht", false, .create),
            ("erstelle mir ein bild der mona lisa", false, .create),
            ("zeichne die mona lisa", false, .create),
            ("mache das bild etwas heller", true, .edit),
            ("wer ist cary elwes", false, .chat),
            ("was ist auf dem foto zu sehen", true, .chat),
        ]
        var agreement = 0
        var generatorTriggered = 0
        for (index, item) in cases.enumerated() {
            let context = SendContext(attachedImage: item.attached)
            let started = ContinuousClock.now
            let decision = await ToolRouter.decide(RouterAsk(baseURL: view.settings.baseURL,
                                                             key: view.settings.apiKey,
                                                             model: view.settings.chatModel, text: item.text,
                                                             context: context, history: [],
                                                             thinking: view.settings.thinkingOffDirective(
                                                              for: view.settings.chatModel)))
            let chosen = decision?.route ?? .chat
            let wish = Wish(route: chosen)
            let same = wish == item.expected
            if same { agreement += 1 }
            if wish == .create || wish == .edit { generatorTriggered += 1 }
            report.add("FALL_\(index)", "gleich=\(same) erwartet=\(item.expected.rawValue) "
                       + "gewählt=\(wish.rawValue) anhang=\(item.attached) "
                       + "suchtext=\(TextLine.oneLine(decision?.pictureQuery ?? "-", limit: 44)) "
                       + "satz=\(TextLine.oneLine(item.text, limit: 44)) "
                       + "ms=\(msOf(started.duration(to: .now)))")
        }
        report.add("TREFFER", "\(agreement)/\(cases.count)")
        let generatorWishes = cases.filter { $0.expected == .create || $0.expected == .edit }.count
        let offered = ToolRouter.tools(attachable: true).contains { tool in
            (tool["function"] as? [String: Any])?["name"] as? String == ToolRouter.findTool
        }
        report.add("BILDGENERATOR", "wünsche=\(generatorWishes) "
                   + "ausgelöst_insgesamt=\(generatorTriggered) bildersuche_werkzeug_am_modell=\(offered)")
        flowLog.info("BILDERSUCHE guard fertig")
    }

    static func flow(_ view: ChatView) async {
        let report = SweepReport(file: "picture_flow.txt")
        guard let answer = await view.ask("finde mir alle bilder vom nordlicht", fresh: true),
              let conversation = view.store.currentID else {
            report.add("KETTENLAUF", "keine antwort")
            return
        }
        let media = view.store.media
        let files = answer.galleryFiles
        let onDisk = files.filter { media.hasImage($0) }.count
        let decoded = await Task.detached(priority: .userInitiated) {
            files.compactMap { MediaStore.thumbnail(media.data(named: $0) ?? Data(),
                                                   maxPixel: ImagePolicy.viewerMaxPixel) }.count
        }.value
        let carried = ConversationMemory.turn(from: [answer]) { media.data(for: $0) }
        report.add("KETTENLAUF", "galerie=\(answer.hasGallery) bilder=\(files.count) auf_derdisk=\(onDisk) "
                   + "dekodiert=\(decoded) erzeugte_bilder=\(answer.outImages?.count ?? 0) "
                   + "quellen=\(answer.sources?.count ?? 0) "
                   + "text=\(TextLine.oneLine(answer.text, limit: 100))")
        report.add("MODELLKONTEXT", "mitgegebene_bilder=\(carried.pictureCount) "
                   + "galerie_im_kontext=\(carried.pictureFiles.contains(where: { files.contains($0) }))")
        report.add("AUFBEWAHRUNG", "referenziert=\(files.allSatisfy { view.store.referencedFiles.contains($0) }) "
                   + "imageFiles_frei=\(answer.imageFiles.isEmpty) speicher=\(view.store.cleaner.usage.imagesLine)")
        await view.morePictures(answer)
        let revealed = view.store.current?.messages.first(where: { $0.id == answer.id })
        report.add("MEHR1", "sichtbar=\(revealed?.gallery?.visiblePictures.count ?? -1) "
                   + "gesamt=\(revealed?.gallery?.pictures.count ?? -1)")
        await view.morePictures(revealed ?? answer)
        let pushed = view.store.current?.messages.first(where: { $0.id == answer.id })
        report.add("MEHR2", "gesamt=\(pushed?.gallery?.pictures.count ?? -1) "
                   + "weiter=\(pushed?.gallery?.nextOffset ?? -1) "
                   + "erschöpft=\(pushed?.gallery?.exhausted ?? true) "
                   + "viewer_dateien=\(pushed?.storedImageFiles.count ?? -1)")
        report.add("UNTEN_DRIN", "unterhaltung=\(conversation == view.store.currentID)")
        flowLog.info("BILDERSUCHE flow fertig")
    }

    static func demo(_ view: ChatView) async {
        _ = await view.ask("finde mir alle bilder von cary elwes", fresh: true)
        flowMark("PICSDEMO nachrichten=\(view.store.current?.messages.count ?? 0) "
                 + "bilder=\(view.store.current?.messages.last?.galleryFiles.count ?? 0)")
    }
}
#endif
