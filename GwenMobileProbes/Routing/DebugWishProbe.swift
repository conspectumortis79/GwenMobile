@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import Foundation

@MainActor
enum DebugWishProbe {
    struct Case {
        let name: String
        let sentence: String
        let expects: [WishExpectation]
    }

    static let monaLisa = ["mona lisa", "monalisa", "mona-lisa", "la gioconda"]
    static let comicStyle = ["comic", "cartoon", "karikatur", "zeichentrick", "illustration", "gezeichnet"]
    static let whoIsShe = ["schauspiel", "actress", "oscar", "black swan", "star wars", "film"]
    static let cat = ["katze", "kater", "katzchen", "cat", "kitten"]
    static let dog = ["hund", "welpe", "dog", "retriever", "labrador", "terrier", "schaferhund", "dackel", "pudel"]

    static let cases: [Case] = [
        Case(name: "zwei_termine_und_mona_lisa_doppelt",
             sentence: "Erstelle 2 Termine, einen Termin um 11 Uhr morgen und einen anderen um 12 Uhr übermorgen, "
             + "dann erstelle ein Bild von der Mona Lisa in Farbe und auch ein Farbbild der Mona Lisa.",
             expects: [.steps([.calendar, .calendar, .picture]),
                       .appointments([AppointmentSlot(dayOffset: 1, hour: 11),
                                      AppointmentSlot(dayOffset: 2, hour: 12)]),
                       .pictures(1), .picture(0, shows: monaLisa, colour: true), .noWarning]),
        Case(name: "route_und_rewe",
             sentence: "Bitte eine Route nach Frankfurter Allee 34 Berlin und bitte mir auch den nächsten "
             + "REWE-Markt zeigen.",
             expects: [.steps([.place, .place]), .placeBlock(heading: "route_head", named: "frankfurter"),
                       .placeBlock(heading: "place_head", named: "rewe"), .noWarning]),
        Case(name: "zwei_termine_ohne_namen",
             sentence: "Erstelle einen Termin morgen um 11 Uhr und einen zweiten Termin übermorgen um 12 Uhr.",
             expects: [.steps([.calendar, .calendar]),
                       .appointments([AppointmentSlot(dayOffset: 1, hour: 11),
                                      AppointmentSlot(dayOffset: 2, hour: 12)]),
                       .pictures(0), .noWarning]),
        Case(name: "mona_lisa_zweimal_derselbe_wunsch",
             sentence: "Erstelle ein Bild von der Mona Lisa in Farbe und auch ein Farbbild der Mona Lisa.",
             expects: [.steps([.picture]), .pictures(1), .picture(0, shows: monaLisa, colour: true),
                       .noWarning]),
        Case(name: "mona_lisa_farbig_dann_schwarzweiss",
             sentence: "Erstelle ein Bild der Mona Lisa in Farbe und danach ein Schwarz-Weiß-Bild der Mona Lisa.",
             expects: [.steps([.picture, .picture]), .pictures(2),
                       .picture(0, shows: monaLisa, colour: true), .picture(1, shows: monaLisa, colour: false),
                       .noWarning]),
        Case(name: "katze_dann_hund",
             sentence: "Male mir eine Katze und danach einen Hund.",
             expects: [.steps([.picture, .picture]), .pictures(2),
                       .picture(0, shows: cat, colour: nil),
                       .picture(1, shows: dog, colour: nil), .noWarning]),
        Case(name: "natalie_wer_und_bilder",
             sentence: "Wer ist Natalie Portman? Zeig mir Bilder von ihr.",
             expects: [.steps([.answer, .gallery]), .pictures(0),
                       .text(all: ["portman"], any: whoIsShe, none: ["dormer"]),
                       .gallery(about: ["natalie", "portman"]), .noWarning]),
        Case(name: "natalie_wer_bilder_comic_rewe",
             sentence: "Wer ist Natalie Portman? Zeig mir Bilder. Und erstelle mir eine Comicfigur von Natalie "
             + "Portman und schau, wo der nächste REWE-Markt ist.",
             expects: [.steps([.answer, .gallery, .picture, .place]),
                       .text(all: ["portman"], any: whoIsShe, none: ["dormer"]),
                       .gallery(about: ["natalie", "portman"]),
                       .pictures(1), .picture(0, shows: comicStyle, colour: nil),
                       .places(named: "rewe"), .noWarning]),
        Case(name: "viele_sieben_wuensche",
             sentence: "Erstelle Termine morgen um 9, um 10 und um 11 Uhr, male eine Katze, zeig mir Bilder vom "
             + "Eiffelturm, sag mir, wer Albert Einstein war, und schau, wo die nächste Apotheke ist.",
             expects: [.steps([.calendar, .calendar, .calendar, .picture, .gallery, .answer, .place]),
                       .appointments([AppointmentSlot(dayOffset: 1, hour: 9), AppointmentSlot(dayOffset: 1, hour: 10),
                                      AppointmentSlot(dayOffset: 1, hour: 11)]),
                       .pictures(1), .picture(0, shows: cat, colour: nil), .gallery(about: ["eiffel"]),
                       .text(all: ["einstein"]), .places(named: "apotheke"), .noWarning]),
        Case(name: "viele_zehn_wuensche",
             sentence: "Trag Termine morgen um 8, 9, 10, 11, 12 und 13 Uhr ein, zeig mir Bilder vom Kölner Dom und "
             + "vom Eiffelturm, sag mir, wie hoch die Zugspitze ist, und wo ist die nächste Apotheke?",
             expects: [.steps([.calendar, .calendar, .calendar, .calendar, .calendar, .calendar,
                               .gallery, .gallery, .answer, .place]),
                       .appointments((8...13).map { AppointmentSlot(dayOffset: 1, hour: $0) }),
                       .pictures(0), .gallery(about: ["koln"]), .gallery(about: ["eiffel"]),
                       .text(all: ["zugspitze"], any: ["2.96", "296", "2 96"]), .places(named: "apotheke"),
                       .noWarning]),
        Case(name: "kontrolle_rewe_markt_allein",
             sentence: "schau wo der nächste rewe markt ist",
             expects: [.steps([.place]), .places(named: "rewe"), .noWarning]),
        Case(name: "kontrolle_rewe_allein",
             sentence: "Wo ist der nächste REWE?",
             expects: [.steps([.place]), .places(named: "rewe"), .noWarning]),
        Case(name: "roh_termine_und_mona_lisa",
             sentence: "erstelle 2 termine, ein termin 11 uhr morgen und ein anderer 12 uhr übermorgen dann ein bild "
             + "erstellen von mona lisa in farbe und auch ein farbbild der monalise",
             expects: [.steps([.calendar, .calendar, .picture]),
                       .appointments([AppointmentSlot(dayOffset: 1, hour: 11),
                                      AppointmentSlot(dayOffset: 2, hour: 12)]),
                       .pictures(1), .picture(0, shows: monaLisa, colour: true), .noWarning]),
        Case(name: "roh_natalie_comic_rewe",
             sentence: "wer ist natalie portman ? zeig mir bilder. und erstelle mir eine comic figur von natalie "
             + "portman und schau wo der nächste rewe markt ist",
             expects: [.steps([.answer, .gallery, .picture, .place]),
                       .text(all: ["portman"], any: whoIsShe, none: ["dormer"]),
                       .gallery(about: ["natalie", "portman"]),
                       .pictures(1), .picture(0, shows: comicStyle, colour: nil),
                       .places(named: "rewe"), .noWarning]),
    ]

    static func sweep(_ view: ChatView) async {
        await run(ProbeRounds.capped(cases), file: "wish_sweep.txt", view: view)
    }

    static let stopSentence = "Trag Termine morgen um 8, 9, 10, 11, 12 und 13 Uhr ein."

    static func stop(_ view: ChatView) async {
        let report = SweepReport(file: "wish_stopp.txt")
        view.store.newConversation()
        view.probeLastPlan = nil
        let now = Date()
        let before = view.store.current?.messages.count ?? 0
        view.input = stopSentence
        flowMark("WUNSCH fall=stopp")
        let finished = LockedValue(false)
        Task {
            await view.send()
            finished.set(true)
        }
        var waited = 0
        while waited < 1200,
              !assistants(in: view, after: before).contains(where: { $0.calendarRef != nil }) {
            try? await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
        let runningBeforeStop = view.probeChainRunning
        view.probeStopChain()
        let completed = await ProbeWait.until(180) { finished.current }
        if !completed {
            view.probeStopRun()
            _ = await ProbeWait.until(30) { finished.current }
        }
        let answers = assistants(in: view, after: before)
        let planned = view.probeLastPlan?.actions.count ?? 0
        let made = answers.compactMap(\.calendarRef).count
        let notice = answers.last?.text ?? ""
        let told = notice.hasPrefix(L.t("chain_stopped").components(separatedBy: "%@").first ?? "-")
        let ok = runningBeforeStop && planned == 6 && made >= 1 && made < planned && told && !view.probeChainRunning
        report.add("STOPP", "ok=\(ok) geplant=\(planned) angelegt=\(made) lief_beim_stopp=\(runningBeforeStop) "
                   + "hinweis=\(told) laeuft_danach=\(view.probeChainRunning) beendet=\(completed) "
                   + "wartezeit_ms=\(waited * 100)")
        report.add("STOPP_HINWEIS", TextLine.oneLine(notice, limit: 160))
        ProbeCalendarSweeper().sweep(created: answers.compactMap(\.calendarRef), since: now.addingTimeInterval(-2),
                                     report: report, label: "STOPP")
        flowLog.info("WUNSCHSTOPP fertig ok=\(ok)")
    }

    private static func assistants(in view: ChatView, after before: Int) -> [ChatMessage] {
        Array((view.store.current?.messages ?? []).dropFirst(before)).filter { $0.role == .assistant }
    }

    private static func run(_ chosen: [Case], file: String, view: ChatView) async {
        let report = SweepReport(file: file)
        report.add("KONFIG", "schluessel=\(view.settings.isConfigured) chat=\(view.settings.chatModel) "
                   + "vision=\(view.settings.visionModel) bild=\(view.settings.imageModel) "
                   + "kalender=\(CalendarService.hasAccess) "
                   + "faelle=\(chosen.count)")
        let inspector = PictureInspector(describer: VisionPictureDescriber(settings: view.settings,
                                                                             media: view.store.media),
                                         media: view.store.media)
        var passed = 0
        for entry in chosen {
            passed += await run(entry, view: view, inspector: inspector, report: report) ? 1 : 0
        }
        report.add("SUMME", "ok=\(passed)/\(chosen.count)")
        flowLog.info("WUNSCH fertig ok=\(passed)/\(chosen.count)")
    }

    private static func run(_ entry: Case, view: ChatView, inspector: PictureInspector,
                            report: SweepReport) async -> Bool {
        let now = Date()
        let answers = await DebugFeatureProbe.freshAsk(view, entry.sentence,
                                                       log: "WUNSCH fall=\(entry.name)", resetPlan: true)
        let steps = view.probeLastPlan?.actions ?? []
        let files = answers.flatMap { ($0.outImages ?? []).map(\.file) }
        let looks = await inspector.looks(at: files)
        let refs = answers.compactMap(\.calendarRef)
        let outcome = WishOutcome(steps: steps, answers: answers, looks: looks,
                                  liveStarts: refs.map { CalendarService.event(for: $0)?.startDate },
                                  now: now)
        let missing = entry.expects.filter { !$0.met(outcome) }.map(\.name)
        let label = "WUNSCH_\(entry.name)"
        let graded = looks.allSatisfy(\.isGradable)
        report.add(label, "ok=\(missing.isEmpty) fehlt=\(missing.isEmpty ? "keins" : missing.joined(separator: ",")) "
                   + (graded ? "" : "bildbewertung=fehlgeschlagen ")
                   + "schritte=\(outcome.stepTrace.isEmpty ? "-" : outcome.stepTrace) antworten=\(answers.count) "
                   + "bilder=\(files.count) termine=\(refs.count)")
        report.add("\(label)_SATZ", TextLine.oneLine(entry.sentence, limit: 200))
        for (index, step) in steps.enumerated() {
            report.add("\(label)_SCHRITT_\(index + 1)", "\(step.stepKind.rawValue) "
                       + TextLine.oneLine(step.stepDetail, limit: 140)
                       + " wunsch=" + TextLine.oneLine(step.wish ?? "-", limit: 120))
        }
        for (index, ref) in refs.enumerated() {
            let live = outcome.liveStarts[index].map { Formatters.eventDateTime($0) } ?? "nicht_im_kalender"
            report.add("\(label)_TERMIN_\(index + 1)", "titel=\(ref.chipTitle) "
                       + "start=\(Formatters.eventDateTime(ref.start)) live=\(live)")
        }
        for (index, look) in looks.enumerated() {
            report.add("\(label)_BILD_\(index + 1)", "chroma=\(String(format: "%.1f", look.chroma)) "
                       + "farbig=\(look.isColour) bewertbar=\(look.isGradable) "
                       + "sicht=\(TextLine.oneLine(look.description, limit: 160))")
        }
        for (index, answer) in answers.enumerated() {
            report.add("\(label)_BLASE_\(index)", DebugChainFixtures.describe(answer))
        }
        ProbeCalendarSweeper().sweep(created: refs, since: now.addingTimeInterval(-2), report: report, label: label)
        return missing.isEmpty
    }
}
#endif
