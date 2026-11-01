@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import UIKit

@MainActor
enum DebugPriceProbe {
    private struct GuardCase {
        let text: String
        let attached: Bool
        let accepted: [Wish]
        let country: String
        let nearby: Bool
    }

    private enum Wish: String {
        case preis = "preisvergleich"
        case suchtext = "websuche"
        case chat = "nur chat"
        case erzeugen = "bild erzeugen"
        case bearbeiten = "bild bearbeiten"
        case anderes = "anderes"

        init(decision: ToolDecision?) {
            guard let decision else { self = .chat; return }
            switch decision.route {
            case .priceSearch: self = .preis
            case .chat: self = decision.searchQuery == nil ? .chat : .suchtext
            case .imageCreate: self = .erzeugen
            case .imageEdit: self = .bearbeiten
            default: self = .anderes
            }
        }
    }

    private static let productTag = "KAFFEEVOLLAUTOMAT\nJURA ENA 4\n799 €\nEAN 7612900407126"
    private static let ask = "Schaue nach, ob du es im Internet günstiger findest"
    private static let macbookAsk = "Was ist das günstigste MacBook 13, das du finden kannst?"
    private static let ean = "7612900407126"

    static func priceScan(_ view: ChatView) async {
        let report = SweepReport(file: "price_scan.txt")
        let settings = view.settings
        report.add("KONFIG", "schluessel=\(settings.isConfigured) chat=\(settings.chatModel) "
                   + "vision=\(settings.visionModel) bild=\(settings.imageModel)")
        guard let picture = tagData() else {
            report.add("ABBILD", "keine jpeg — abbruch")
            return
        }
        guard let finding = await scanOnce(view, picture: picture, report: report) else {
            report.add("BEFUND_TREFFER", "jura=false ena=false euro=false ean=false")
            return
        }
        report.add("BEFUND", "produkt=\(TextLine.oneLine(finding.product, limit: 40)) "
                   + "marke=\(finding.brand) preis=\(finding.price) ean=\(finding.ean) "
                   + "lesedauer_begriffe=\(finding.identityTerms.count)")
        report.add("BEFUND_TREFFER", "jura=\(finding.product.lowercased().contains("jura")) "
                   + "ena=\(finding.product.uppercased().contains("ENA")) "
                   + "euro=\(finding.price.contains("799")) ean=\(finding.ean.contains(Self.ean))")
        await routerStep(view, picture: picture, report: report)
        researchStep(view, finding: finding, picture: picture, report: report)
        await lookupStep(report, terms: finding.identityTerms)
        flowLog.info("PREISSCAN fertig")
    }

    static func routeGuard(_ view: ChatView) async {
        let report = SweepReport(file: "price_guard.txt")
        let cases = [
            GuardCase(text: ask, attached: true, accepted: [.preis], country: "", nearby: false),
            GuardCase(text: "was kostet das Gerät online wirklich?", attached: true,
                      accepted: [.preis], country: "", nearby: false),
            GuardCase(text: "kannst du das irgendwo günstiger finden?", attached: true,
                      accepted: [.preis], country: "", nearby: false),
            GuardCase(text: "wo kann ich den Kaffeevollautomaten billig kaufen?", attached: true,
                      accepted: [.preis], country: "", nearby: false),
            GuardCase(text: "was kostet eine Jura ENA 4?", attached: false,
                      accepted: [.preis], country: "", nearby: false),
            GuardCase(text: "gibt es den Kaffeevollautomaten in Polen günstiger?", attached: false,
                      accepted: [.preis], country: "PL", nearby: false),
            GuardCase(text: "wie viel kostet das hier bei mir im Laden?", attached: true,
                      accepted: [.preis], country: "", nearby: true),
            GuardCase(text: "was ist auf dem foto zu sehen", attached: true,
                      accepted: [.chat], country: "", nearby: false),
            GuardCase(text: "Übersetze den Text auf dem Foto ins Englische", attached: true,
                      accepted: [.chat], country: "", nearby: false),
            GuardCase(text: "zeichne mir ein Bild von dem Gerät", attached: true,
                      accepted: [.erzeugen], country: "", nearby: false),
            GuardCase(text: "wer hat 2026 den Eurovision Song Contest gewonnen", attached: false,
                      accepted: [.suchtext], country: "", nearby: false),
            GuardCase(text: "wie viele Preise hat der Sportler xy schon bekommen?", attached: false,
                      accepted: [.suchtext, .chat], country: "", nearby: false),
            GuardCase(text: "welches Preisgeld gab es beim Turnier 2026?", attached: false,
                      accepted: [.suchtext, .chat], country: "", nearby: false),
            GuardCase(text: "was kostet ein Studium in Deutschland?", attached: false,
                      accepted: [.suchtext, .chat], country: "", nearby: false),
            GuardCase(text: "der preis des sieges war hohe konzentration", attached: false,
                      accepted: [.chat], country: "", nearby: false),
        ]
        let offered = ToolRouter.tools(attachable: true).contains { tool in
            (tool["function"] as? [String: Any])?["name"] as? String == ToolRouter.priceTool
        }
        report.add("WERKZEUG", "am_modell=\(offered) name=\(ToolRouter.priceTool) "
                   + "budget=\(ToolRouter.maxTokens)")
        var agreement = 0
        var wrongPriceTriggers = 0
        for (index, item) in cases.enumerated() {
            let run = await decide(view, text: item.text, attached: item.attached)
            let chosen = Wish(decision: run.outcome)
            let flags = routeFlags(run.outcome)
            let believed = PriceRegion.claimed(flags.country, in: item.text)?.code ?? ""
            let rightFlags = believed == item.country && flags.nearby == item.nearby
            let same = item.accepted.contains(chosen) && rightFlags
            let wronglyPrice = chosen == .preis && !item.accepted.contains(.preis)
            if same { agreement += 1 }
            if wronglyPrice { wrongPriceTriggers += 1 }
            report.add("FALL_\(index)", "gleich=\(same) erlaubt=\(names(item.accepted)) "
                       + "gewählt=\(chosen.rawValue) route=\(routeName(run.outcome)) "
                       + "preisGetriggert=\(chosen == .preis) "
                       + "anhang=\(item.attached) "
                       + "router=\(run.skipped ? "übersprungen" : "gefragt") "
                       + "land=\(believed.isEmpty ? "-" : believed) "
                       + "landRoh=\(flags.country ?? "-") "
                       + "erwartetLand=\(item.country.isEmpty ? "-" : item.country) "
                       + "nahe=\(flags.nearby) erwartetNahe=\(item.nearby) "
                       + "terms=\(TextLine.oneLine(terms(of: run.outcome).joined(separator: "|"), limit: 40)) "
                       + "befund=\(TextLine.oneLine(run.finding?.traceLine ?? "-", limit: 36)) "
                       + "satz=\(TextLine.oneLine(item.text, limit: 36))")
        }
        report.add("TREFFER", "\(agreement)/\(cases.count)")
        report.add("PREIS_TRIGGER_FALSCH", "\(wrongPriceTriggers) "
                   + "(erwartet 0 — kein Satz ohne Kaufwunsch darf die Preissuche starten)")
        flowLog.info("PREISGUARD fertig")
    }

    static func trigger(_ view: ChatView) async {
        let report = SweepReport(file: "price_trigger.txt")
        let sentences = [ask,
                         "wie viele Preise hat der Tennisspieler Roger Federer gewonnen?",
                         "welche Preise hat der Film gewonnen?"]
        for state in ["ohne_bild", "erinnertes_bild", "frischer_anhang"] {
            prepare(view, state: state)
            let turn = ConversationMemory.turn(from: view.store.current?.messages ?? []) {
                view.store.media.data(for: $0)
            }
            report.add(state.uppercased(), "bilder_im_turn=\(turn.images.count) "
                       + "am_letzten_satz=\(turn.messages.last?.images.count ?? -1)")
            for (index, sentence) in sentences.enumerated() {
                let context = SendContext(attachedImage: turn.messages.last?.images.isEmpty == false,
                                          rememberedImage: turn.images.isEmpty == false
                                              && turn.messages.last?.images.isEmpty != false)
                let skipped = ToolRouter.carriesOnlyPictures(text: sentence, pictures: turn.images.count)
                let history = view.store.current?.messages ?? []
                let textModel = view.settings.chatModel
                let visionModel = view.settings.answeringModel(hasPictures: true)
                let withoutPicture = skipped ? nil : await ToolRouter.decide(
                    RouterAsk(baseURL: view.settings.baseURL, key: view.settings.apiKey,
                              model: textModel, text: sentence, context: context, history: history,
                              thinking: view.settings.thinkingOffDirective(for: textModel)))
                let withPicture = skipped ? nil : await ToolRouter.decide(
                    RouterAsk(baseURL: view.settings.baseURL, key: view.settings.apiKey,
                              model: visionModel, text: sentence, context: context, history: history,
                              picture: turn.images.last,
                              thinking: view.settings.thinkingOffDirective(for: visionModel)))
                let chosen = Wish(decision: withPicture)
                let attaches = turn.messages.last?.images.isEmpty == false
                report.add("SATZ_\(index)",
                           "bild_fehlt=\(Wish(decision: withoutPicture).rawValue) "
                           + "bild_dabei=\(chosen.rawValue) "
                           + "scan=\(!skipped && chosen == .preis && attaches) "
                           + "anhang=\(attaches) "
                           + "terms=\(TextLine.oneLine(terms(of: withPicture).joined(separator: "|"), limit: 40)) "
                           + "satz=\(TextLine.oneLine(sentence, limit: 40))")
            }
        }
        flowLog.info("PREISTRIGGER fertig")
    }

    static func badge(_ view: ChatView) async {
        let report = SweepReport(file: "price_badge.txt")
        for state in ["ohne_bild", "erinnertes_bild", "frischer_anhang"] {
            report.add(state.uppercased(), await badgeRun(view, state: state))
            flowLog.info("PREISBADGE \(state) fertig")
        }
        flowLog.info("PREISBADGE fertig")
    }

    @MainActor private static func sampling(_ interval: Int, of read: @escaping @MainActor () -> String,
                                            during body: @MainActor () async -> Void) async -> [String] {
        let stop = LockedValue(false)
        let seen = LockedValue([String]())
        let watcher = Task { @MainActor in
            let deadline = ContinuousClock.now + .seconds(300)
            while !stop.current, ContinuousClock.now < deadline {
                seen.mutate { $0.append(read()) }
                try? await Task.sleep(for: .milliseconds(interval))
            }
        }
        await body()
        stop.set(true)
        watcher.cancel()
        return seen.current
    }

    private static func badgeRun(_ view: ChatView, state: String) async -> String {
        prepare(view, state: state == "frischer_anhang" ? "ohne_bild" : state)
        if state == "frischer_anhang" {
            view.pendingImages = [PendingPicture(image: tag(), file: nil)]
        }
        view.input = macbookAsk
        let labels = Set(await sampling(250, of: { view.probeBusyLabel }) { await view.send() }
            .filter { !$0.isEmpty })
        let reads = labels.contains(L.t("product_reading"))
        let compares = labels.contains(L.t("price_working"))
        let answer = view.lastAnswer
        let names = labels.sorted().joined(separator: " | ")
        return "leseBadge=\(reads) preisBadge=\(compares) anhang=\(state == "frischer_anhang") "
            + "labels=\(TextLine.oneLine(names, limit: 80)) "
            + "quellen=\(answer?.sources?.count ?? -1) überschrift=\(answer?.sourcesHeadingKey ?? "-")"
    }

    private static func prepare(_ view: ChatView, state: String) {
        view.store.newConversation()
        guard let id = view.store.currentID else { return }
        guard state != "ohne_bild" else {
            view.store.appendMessage(ChatMessage(role: .user, text: "Hallo"), to: id)
            return
        }
        let file = view.store.media.store(tag())
        guard let file else { return }
        let attachment = Attachment(file: file)
        if state == "frischer_anhang" {
            view.store.appendMessage(ChatMessage(role: .user, text: ask, images: [attachment]), to: id)
            return
        }
        view.store.appendMessage(ChatMessage(role: .user, text: "Vorher ein Foto",
                                            images: [attachment]), to: id)
        view.store.appendAssistant("Das ist ein Kaffeevollautomat.", model: "probe", elapsed: nil, to: id)
    }

    private static func routeName(_ decision: ToolDecision?) -> String {
        guard let route = decision?.route else { return "keine" }
        switch route {
        case .priceSearch: return "preisvergleich"
        case .priceWatch: return "preiswecker"
        case .dayBriefing: return "tagesbriefing"
        case .chat: return "chat"
        case .imageCreate: return "erzeugen"
        case .imageEdit: return "bearbeiten"
        case .videoCreate: return "video"
        case .pictureSearch: return "bildersuche"
        case .nearbyPlace: return "orte_in_der_naehe"
        case .routeToPlace: return "route"
        case .calendar: return "kalender"
        case .reminder: return "erinnerung"
        case .timer: return "timer"
        case .readAloud: return "vorlesen"
        case .readAnswer: return "antwort_vorlesen"
        case .code: return "code"
        case .translate: return "uebersetzen"
        case .scanDocument: return "scan"
        case .call: return "anruf"
        case .clock: return "uhrzeit"
        case .music: return "musik"
        case .message: return "nachricht"
        case .memory: return "gedaechtnis"
        case .history: return "verlauf"
        case .weather: return "wetter"
        case .appStatus: return "status"
        }
    }

    private static func names(_ wishes: [Wish]) -> String {
        wishes.map { $0.rawValue }.joined(separator: "/")
    }

    @MainActor private static func askWithPhoto(_ view: ChatView) async {
        view.store.newConversation()
        try? await Task.sleep(for: .milliseconds(600))
        view.pendingImages = [PendingPicture(image: tag(), file: nil)]
        view.input = ask
    }

    static func pricePath(_ view: ChatView) async {
        let report = SweepReport(file: "price_path.txt")
        await askWithPhoto(view)
        let started = ContinuousClock.now
        await view.send()
        let answer = view.lastAnswer
        let sources = answer?.sources ?? []
        let text = answer?.text ?? ""
        report.add("SEND", "ms=\(msOf(started.duration(to: .now))) modell=\(answer?.model ?? "-") "
                   + "zeichen=\(text.count) quellen=\(sources.count) "
                   + "überschrift=\(answer?.sourcesHeadingKey ?? "-") "
                   + "domains=\(TextLine.oneLine(sources.map(\.domain).joined(separator: ","), limit: 110))")
        report.add("KAPSEL", "danach=\(view.webStatus ?? "nil")")
        report.add("ANTWORT", TextLine.oneLine(text, limit: 300))
        report.add("SEND_TREFFER", "quellen=\(sources.count >= 1) "
                   + "angebote=\(answer?.sourcesHeadingKey == PriceComparator.headingKey) "
                   + "preisGenannt=\(text.contains("€")) "
                   + "anhangImChat=\(view.store.current?.messages.contains { !$0.images.isEmpty } ?? false) "
                   + "keinProtokollToken=\(!text.contains(SearchMarker.token))")
        flowLog.info("PREISPFAD fertig")
    }

    static func capsule(_ view: ChatView) async {
        let report = SweepReport(file: "price_capsule.txt")
        report.add("KONFIG", "schluessel=\(view.settings.isConfigured) chat=\(view.settings.chatModel) "
                   + "vision=\(view.settings.visionModel) basis=\(view.settings.baseURL)")
        report.add("FEHLPFAD_OHNE_NETZ", await failureLine())
        await capsuleRound(view, report: report)
        if view.settings.isConfigured {
            await sendRound(view, report: report)
        } else {
            report.add("SKIP_SEND", "grund=kein api-schlüssel auf diesem gerät — send() würde nur die "
                       + "einstellungen öffnen, ein echter preislauf braucht das konto")
        }
        flowLog.info("PREISKAPSEL fertig")
    }

    private static func capsuleRound(_ view: ChatView, report: SweepReport) async {
        var geworfen = "-"
        var quellen = -1
        let started = ContinuousClock.now
        let samples = await sampling(300, of: { view.webStatus ?? "nil" }) {
            do {
                quellen = try await WebPriceLookup { status in view.webStatus = status }
                    .hits(for: ["Jura ENA 4"], region: PriceRegion.device()).count
            } catch let error as APIError {
                geworfen = error.message
            } catch {
                geworfen = error.localizedDescription
            }
        }
        report.add("KAPSEL_RUND_ECHT", "quellen=\(quellen) würfe=\(TextLine.oneLine(geworfen, limit: 40)) "
                   + "sample=\(samples.count) gesetzt=\(samples.filter { $0 != "nil" }.count) "
                   + "erste=\(TextLine.oneLine(samples.first ?? "-", limit: 34)) "
                   + "letzte=\(TextLine.oneLine(samples.last ?? "-", limit: 34)) "
                   + "ms=\(msOf(started.duration(to: .now)))")
        report.add("KAPSEL_RUND_TREFFER", "gezeigt=\(samples.contains { $0 != "nil" }) "
                   + "zuEnde=\(view.webStatus == nil)")
    }

    private static func sendRound(_ view: ChatView, report: SweepReport) async {
        var elapsed = 0
        let samples = await sampling(400, of: { view.webStatus ?? "nil" }) {
            await askWithPhoto(view)
            let started = ContinuousClock.now
            await view.send()
            elapsed = msOf(started.duration(to: .now))
        }
        let answer = view.lastAnswer
        let sources = answer?.sources ?? []
        report.add("VERLAUF", "sample=\(samples.count) gesetzt=\(samples.filter { $0 != "nil" }.count) "
                   + "erste=\(TextLine.oneLine(samples.first ?? "-", limit: 40)) "
                   + "letzte=\(TextLine.oneLine(samples.last ?? "-", limit: 40)) "
                   + "ms=\(elapsed)")
        report.add("ANTWORT", "quellen=\(sources.count) überschrift=\(answer?.sourcesHeadingKey ?? "-") "
                   + "zeichen=\(answer?.text.count ?? -1)")
        report.add("KAPSEL_ENDE", "danach=\(view.webStatus ?? "nil")")
        report.add("KAPSEL_TREFFER", "gezeigt=\(samples.contains { $0 != "nil" }) "
                   + "zuEnde=\(view.webStatus == nil) "
                   + "antwortDa=\(sources.count >= 1 && answer?.sourcesHeadingKey == PriceComparator.headingKey)")
    }

    private static func failureLine() async -> String {
        let texts = LockedValue(0)
        let ends = LockedValue(0)
        let erste = LockedValue("-")
        var geworfen = "-"
        do {
            _ = try await WebPriceLookup(onStatus: { status in
                if let status {
                    texts.mutate { $0 += 1 }
                    if erste.current == "-" { erste.set(status) }
                } else {
                    ends.mutate { $0 += 1 }
                }
            }).hits(for: [], region: .device())
        } catch let error as APIError {
            geworfen = error.message
        } catch {
            geworfen = error.localizedDescription
        }
        return "würfe=\(TextLine.oneLine(geworfen, limit: 40)) texts=\(texts.current) "
            + "erste=\(TextLine.oneLine(erste.current, limit: 30)) ende=\(ends.current)"
    }

    private static func scanOnce(_ view: ChatView, picture: Data,
                                 report: SweepReport) async -> ProductFinding? {
        let settings = view.settings
        let model = settings.answeringModel(hasPictures: true)
        do {
            let found = try await VisionProductScanner().scan(baseURL: settings.baseURL,
                                                              key: settings.apiKey, model: model,
                                                              question: ask, image: picture,
                                                              thinking: settings.thinkingOffDirective(for: model))
            if found == nil { report.add("BEFUND", "kein verwertbares ergebnis") }
            return found
        } catch {
            report.addFailure("BEFUND", error)
            return nil
        }
    }

    private static func decide(_ view: ChatView, text: String,
                               attached: Bool) async -> (outcome: ToolDecision?, finding: ProductFinding?,
                                                          skipped: Bool) {
        let settings = view.settings
        let context = SendContext(attachedImage: attached)
        let skipped = ToolRouter.carriesOnlyPictures(text: text, pictures: attached ? 1 : 0)
        guard !skipped else { return (nil, nil, true) }
        let model = settings.answeringModel(hasPictures: attached)
        let decision = await ToolRouter.decide(RouterAsk(baseURL: settings.baseURL, key: settings.apiKey,
                                                         model: model, text: text, context: context,
                                                         history: [], picture: attached ? tagData() : nil,
                                                         thinking: settings.thinkingOffDirective(for: model)))
        let buys = Wish(decision: decision) == .preis
        let finding = buys && attached ? try? await readTag(view, question: text) : nil
        return (decision, finding, false)
    }

    private static func readTag(_ view: ChatView, question: String) async throws -> ProductFinding? {
        let settings = view.settings
        let model = settings.answeringModel(hasPictures: true)
        guard let picture = tagData() else { return nil }
        return try await VisionProductScanner().scan(baseURL: settings.baseURL, key: settings.apiKey,
                                                    model: model, question: question, image: picture,
                                                    thinking: settings.thinkingOffDirective(for: model))
    }

    private static func routerStep(_ view: ChatView, picture: Data,
                                   report: SweepReport) async {
        let settings = view.settings
        let model = settings.answeringModel(hasPictures: true)
        let started = ContinuousClock.now
        let decision = await ToolRouter.decide(RouterAsk(baseURL: settings.baseURL, key: settings.apiKey,
                                                         model: model, text: ask,
                                                         context: SendContext(attachedImage: true),
                                                         history: [], picture: picture,
                                                         thinking: settings.thinkingOffDirective(for: model)))
        let wish = Wish(decision: decision)
        report.add("ROUTER", "werkzeug=\(wish.rawValue) erwartet=\(Wish.preis.rawValue) "
                   + "gleich=\(wish == .preis) "
                   + "terms=\(TextLine.oneLine(terms(of: decision).joined(separator: "|"), limit: 60)) "
                   + "ms=\(msOf(started.duration(to: .now)))")
    }

    private static func researchStep(_ view: ChatView, finding _: ProductFinding, picture: Data,
                                     report: SweepReport) {
        let source = WebHit(title: "Idealo", url: "https://idealo.de/p/jura-ena-4", domain: "idealo.de",
                            text: "Jura ENA 4 Kaffeevollautomat — 612,00 € im Preisvergleich.")
        do {
            let request = try WebSearch.makeAnswerRequest(baseURL: view.settings.baseURL,
                                                          key: view.settings.apiKey,
                                                          model: view.settings.chatModel,
                                                          question: "gibt es den günstiger?",
                                                          hits: [source], history: [], images: [picture],
                                                          thinking: .nothing)
            let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
            let messages = (body?["messages"] as? [[String: Any]]) ?? []
            let content = messages.last?["content"]
            let parts = (content as? [[String: Any]]) ?? []
            let text = (parts.first?["text"] as? String) ?? (content as? String) ?? ""
            report.add("RECHERCHE", "format=\(content is String ? "text" : "teile") "
                       + "teile=\(parts.count) bilder=\(parts.filter { $0["image_url"] != nil }.count) "
                       + "befundblock=\(text.contains("## IMAGE FINDING")) "
                       + "nutzerpreis=\(text.contains("price shown on the picture")) "
                       + "quelle=\(text.contains("## SOURCE [1]"))")
        } catch {
            report.addFailure("RECHERCHE", error)
        }
    }

    private static func lookupStep(_ report: SweepReport, terms: [String]) async {
        let steps = LockedValue(0)
        let ends = LockedValue(0)
        do {
            let started = ContinuousClock.now
            let hits = try await WebPriceLookup(onStatus: { status in
                if status == nil { ends.mutate { $0 += 1 } } else { steps.mutate { $0 += 1 } }
            }).hits(for: terms, region: PriceRegion.device())
            let priced = PriceEvidence.withPrice(hits)
            report.add("PREISSUCHE", "begriffe=\(TextLine.oneLine(terms.joined(separator: "|"), limit: 50)) "
                       + "quellen=\(hits.count) preisTreffer=\(priced.count) "
                       + "domains=\(TextLine.oneLine(hits.map(\.domain).joined(separator: ","), limit: 110)) "
                       + "statuszeilen=\(steps.current) kapselEnde=\(ends.current == 1) "
                       + "ms=\(msOf(started.duration(to: .now)))")
        } catch {
            report.add("PREISSUCHE", "fehler=\(TextLine.oneLine(error.localizedDescription, limit: 90)) "
                       + "statuszeilen=\(steps.current) kapselEnde=\(ends.current == 1)")
        }
    }

    static func region(_ view: ChatView) async {
        let report = SweepReport(file: "price_region.txt")
        let device = PriceRegion.device()
        report.add("GERÄT", "\(device.traceLine) label=\(device.label ?? "-")")
        for name in ["DE", "de", "Polen", "germany", "Schweiz", "Vereinigte Staaten",
                     "UK", "USA", "England", "idealo", "xy"] {
            let found = PriceRegion.named(name).map { "\($0.code ?? "-")/\($0.source.rawValue)" } ?? "keins"
            report.add("LAND", "\(name) → \(found)")
        }
        var currencies: [String] = []
        for code in ["DE", "PL", "CH", "US", "GB"] {
            guard let region = PriceRegion.named(code) else { continue }
            currencies.append("\(code)=\(region.currencyCode ?? "-")")
        }
        report.add("WÄHRUNG", currencies.joined(separator: " "))
        await parameterLines(report)
        await readerLines(view, report: report)
        flowLog.info("PREISREGION fertig")
    }

    private static func parameterLines(_ report: SweepReport) async {
        let neutral = "Jura ENA 4"
        let ohne = await searched(neutral, region: nil)
        let de = await searched(neutral, region: "DE")
        let pl = await searched(neutral, region: "PL")
        report.add("URL", requestLine(neutral))
        report.add("FRAGE_OHNE_PARAM", "treffer=\(ohne.count) domains=\(domainList(ohne))")
        report.add("FRAGE_DE", "treffer=\(de.count) domains=\(domainList(de)) "
                   + "überschneidung_ohne=\(shared(ohne, de)) neu=\(added(de, ohne))")
        report.add("FRAGE_PL", "treffer=\(pl.count) domains=\(domainList(pl)) "
                   + "überschneidung_ohne=\(shared(pl, ohne)) polnisch=\(countPl(pl))")
        let wording = await searched("Ekspres do kawy cena", region: "PL")
        report.add("FRAGE_PL_WORT", "treffer=\(wording.count) domains=\(domainList(wording)) "
                   + "polnisch=\(countPl(wording))")
    }

    private static func shared(_ left: [URL], _ right: [URL]) -> Int {
        Set(left).intersection(Set(right)).count
    }

    private static func added(_ left: [URL], _ right: [URL]) -> Int {
        Set(left).subtracting(Set(right)).count
    }

    private static func countPl(_ urls: [URL]) -> Int {
        urls.filter { WebSearch.domain(of: $0).hasSuffix(".pl") }.count
    }

    private static func readerLines(_: ChatView, report: SweepReport) async {
        let reader = LivePriceRegionReading()
        let named = await reader.region(named: "Polen", whenLocalWish: false)
        let plain = await reader.region(named: nil, whenLocalWish: false)
        report.add("LESER", "genannt=\(named.traceLine) gerät=\(plain.traceLine)")
        let started = ContinuousClock.now
        let local = await reader.region(named: nil, whenLocalWish: true)
        report.add("LESER_STANDORT", "\(local.traceLine) ms=\(msOf(started.duration(to: .now))) "
                   + "hinweis=standortabfrage_kann_berechtigung_verlangen")
    }

    private static func searched(_ query: String, region: String?) async -> [URL] {
        (try? await WebSearch.searchURLs(query, region: region)) ?? []
    }

    private static func requestLine(_ query: String) -> String {
        guard let url = try? WebSearch.searchRequest(query, region: "DE").url else { return "kaputt" }
        return TextLine.oneLine(url.absoluteString, limit: 90)
    }

    private static func domainList(_ urls: [URL]) -> String {
        TextLine.oneLine(urls.map { WebSearch.root(ofDomain: WebSearch.domain(of: $0)) }
            .joined(separator: ","), limit: 90)
    }

    private static func routeFlags(_ decision: ToolDecision?) -> (country: String?, nearby: Bool) {
        guard case .priceSearch(_, let country, let nearby)? = decision?.route else { return (nil, false) }
        return (country, nearby)
    }

    private static func terms(of decision: ToolDecision?) -> [String] {
        guard case .priceSearch(let terms, _, _)? = decision?.route else { return [] }
        return terms
    }

    static func tag() -> UIImage {
        ReceiptCard.receiptCard(fontSize: 54, text: productTag, lineSpacing: 18)
    }

    private static func tagData() -> Data? {
        tag().jpegData(compressionQuality: 0.9)
    }
}
#endif
