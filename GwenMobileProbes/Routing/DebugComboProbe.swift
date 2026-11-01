@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import UIKit

@MainActor
enum DebugComboProbe {
    private enum Shot {
        case none
        case shape(PictureProbe.Fixture)
        case tag
        case note
    }

    private struct Entry {
        let name: String
        let section: String
        let sentence: String
        let expects: [TurnExpectation]
        var shot: Shot = .none
        var cameraShot = false
        var fileText: String?
        var marker: String?
    }

    private static let lagerNotiz = "Punkt 4.2: Für den Ausbau des Lagers sind 85.000 Euro vorgesehen. "
        + "Termin: nächste Woche, 03.07. Der Rat stimmt am Freitag ab."

    private static let mona = "Erstelle ein Bild der Mona Lisa in Schwarz-Weiß"

    private static let entries: [Entry] = [
        Entry(name: "anhang_bild_dann_preissuche", section: "anhang",
              sentence: "Was für ein Gerät ist auf dem Foto? Such mir das günstigste Angebot mit dieser EAN.",
              expects: [.text, .priceRounds(1)], shot: .tag),
        Entry(name: "anhang_bild_dann_galerie", section: "anhang",
              sentence: "Was siehst du auf dem Bild? Such mir außerdem Bilder von demselben Motiv.",
              expects: [.text, .gallery], shot: .shape(PictureProbe.circle)),
        Entry(name: "anhang_bild_dann_schwarzweiss", section: "anhang",
              sentence: "Was siehst du auf dem Bild? Ändere das Bild bitte in Schwarz-Weiß.",
              expects: [.text, .exactly(1)], shot: .shape(PictureProbe.star)),
        Entry(name: "anhang_bild_zwei_eingriffe", section: "anhang",
              sentence: "Mach das Bild zuerst heller und danach schwarz-weiß.",
              expects: [.picture], shot: .shape(PictureProbe.square)),

        Entry(name: "kamera_bild_dann_preissuche", section: "kamera",
              sentence: "Ist das der beste Preis? Finde das günstigste Angebot im Internet.",
              expects: [.priceRounds(1)], shot: .tag, cameraShot: true),
        Entry(name: "kamera_bild_dann_termin", section: "kalender",
              sentence: "Was ist auf dem Foto? Trag für morgen 18 Uhr einen Termin GwenKamera ein.",
              expects: [.text, .appointment], shot: .shape(PictureProbe.triangle),
              cameraShot: true, marker: "GwenKamera"),

        Entry(name: "datei_fass_dann_galerie", section: "datei",
              sentence: "Fasse zusammen, was in der Datei steht, und such mir Bilder zum Thema Lagerausbau.",
              expects: [.text, .gallery], fileText: lagerNotiz),
        Entry(name: "datei_fass_dann_termin", section: "kalender",
              sentence: "Fasse die Datei zusammen und trag für morgen 10 Uhr einen Termin GwenDatei ein.",
              expects: [.text, .appointment], fileText: lagerNotiz, marker: "GwenDatei"),
        Entry(name: "datei_fass_dann_preissuche", section: "datei",
              sentence: "Fasse die Datei zusammen und such mir die günstigsten Regale für den Lagerausbau.",
              expects: [.text, .priceRounds(1)], fileText: lagerNotiz),
        Entry(name: "datei_fass_dann_polnisch", section: "datei",
              sentence: "Fasse die Datei zusammen und übersetze die Zusammenfassung ins Polnische.",
              expects: [.text, .any(label: "polnisch",
                                     list: ["piątek", "lipca", "przyszłym", "tydzień"])],
              fileText: lagerNotiz),

        Entry(name: "nachrichten_dann_zusatzfrage", section: "nachrichten",
              sentence: "Zeig mir Nachrichten aus Berlin und sag mir, ob der Senat über das Lager abstimmt.",
              expects: [.text, .sources]),
        Entry(name: "nachrichten_dann_preissuche", section: "nachrichten",
              sentence: "Zeig mir Nachrichten aus Berlin und such mir das günstigste MacBook Pro 14 Zoll "
              + "mit 128 GB RAM und 2 TB SSD.",
              expects: [.text, .priceRounds(1)]),
        Entry(name: "nachrichten_dann_kino", section: "nachrichten",
              sentence: "Zeig mir Nachrichten aus Berlin und sag mir, wo das nächste Kino ist.",
              expects: [.text, .sources, .places]),

        Entry(name: "galerie_dann_preissuche", section: "preise",
              sentence: "Zeige mir Bilder vom MacBook Pro 14 Zoll und suche nach dem günstigsten MacBook Pro "
              + "mit 128 GB RAM und 2 TB SSD.",
              expects: [.gallery, .priceRounds(1)]),
        Entry(name: "zwei_preise_und_galerie", section: "preise",
              sentence: "Such mir die Preise für ein MacBook Pro 13 mit 32 GB RAM und 1 TB SSD und für "
              + "einen Mac Studio M5 Ultra mit 256 GB RAM und 1 TB SSD, und zeig mir auch Bilder vom "
              + "Mac Studio M5 Ultra.",
              expects: [.priceRounds(2), .gallery]),
        Entry(name: "zwei_preise_verschiedene_geraete", section: "preise",
              sentence: "Such mir das günstigste MacBook Pro 13 mit 32 GB RAM und 1 TB SSD und das "
              + "günstigste Mac Studio M5 Ultra mit 256 GB RAM und 1 TB SSD.",
              expects: [.priceRounds(2)]),
        Entry(name: "vergleich_zwischen_zwei_macbooks", section: "vergleich",
              sentence: "vergleiche die preise zwischen einem MacBook pro 14\u{201C} 64GB RAM 1TB SSD und MacBook pro "
              + "16\u{201C} 48GB RAM 1TB SSD",
              expects: [.priceRounds(2), .bubbleMentions(0, "14"), .bubbleMentions(1, "16"),
                        .bubbleMentions(1, "48")]),
        Entry(name: "preise_von_zwei_macbooks", section: "vergleich",
              sentence: "Vergleiche die Preise von einem MacBook Pro 14 Zoll mit 64 GB RAM und 1 TB SSD und einem "
              + "MacBook Pro 16 Zoll mit 48 GB RAM und 1 TB SSD.",
              expects: [.priceRounds(2), .bubbleMentions(0, "14"), .bubbleMentions(1, "16"),
                        .bubbleMentions(1, "48")]),

        Entry(name: "ball_und_davon_schwarzweiss", section: "bilder",
              sentence: "Male einen roten Ball auf weißem Grund. Mach das neue Bild danach schwarz-weiß.",
              expects: [.exactly(2), .once(label: "notiz", word: "Hier ist dein bearbeitetes Bild")]),
        Entry(name: "drei_bildvarianten_ein_satz", section: "bilder",
              sentence: "Erstelle mir ein Bild eines roten Balls mit weißem Hintergrund, davon auch ein "
              + "Schwarz-Weiß-Bild und davon auch ein comic-artiges Bild.",
              expects: [.exactly(3)]),
        Entry(name: "zwei_motive", section: "bilder",
              sentence: "\(mona) und erstelle ein Bild eines Leuchtturms bei Nacht.",
              expects: [.exactly(2)]),
        Entry(name: "gleiches_motiv_zwei_farben", section: "bilder",
              sentence: "\(mona) und erstelle ein Bild der Mona Lisa mit deutlichem Gelbstich.",
              expects: [.exactly(2)]),
        Entry(name: "zweimal_gleicher_auftrag", section: "bilder",
              sentence: "\(mona) und erstelle ein Bild der Mona Lisa in Schwarz-Weiß.",
              expects: [.exactly(1)]),

        Entry(name: "route_dann_strecke", section: "karten",
              sentence: "Rout mich mit dem Rad zur Stadtbibliothek und sag mir, wie weit das ist.",
              expects: [.places, .text]),
        Entry(name: "route_dann_termin", section: "kalender",
              sentence: "Rout mich mit dem Auto zum Hauptbahnhof und trag für morgen 8 Uhr einen Termin "
              + "GwenRoute ein.",
              expects: [.places, .appointment], marker: "GwenRoute"),
        Entry(name: "apotheke_dann_route", section: "karten",
              sentence: "Such die nächste Apotheke und rout mich zu Fuß hin.",
              expects: [.places]),
        Entry(name: "termin_dann_zweiter_termin", section: "kalender",
              sentence: "Trag für morgen 10 Uhr einen Termin GwenA ein und für übermorgen 9 Uhr einen "
              + "Termin GwenB.",
              expects: [.appointments(2)], marker: "Gwen"),
        Entry(name: "foto_text_dann_englisch", section: "datei",
              sentence: "Was steht auf dem Foto? Übersetze es ins Englische.",
              expects: [.text, .any(label: "englisch", list: ["workbench", "euro", "friday"])],
              shot: .note),
    ]

    static func sweep(_ view: ChatView) async {
        await run(ProbeRounds.capped(entries), named: "combo_sweep.txt", view: view)
    }

    private static func run(_ chosen: [Entry], named file: String, view: ChatView) async {
        let report = SweepReport(file: file)
        PictureProbe.materialise(in: view.store.media)
        report.add("KONFIG", "schluessel=\(view.settings.isConfigured) chat=\(view.settings.chatModel) "
                   + "bild=\(view.settings.imageModel) preis=\(ToolRouter.priceTool) "
                   + "faelle=\(chosen.count)")
        var passed = 0
        for entry in chosen {
            let ok = await single(entry, view: view, report: report)
            passed += ok ? 1 : 0
        }
        report.add("SUMME", "ok=\(passed)/\(chosen.count)")
        flowLog.info("KOMBO fertig ok=\(passed)/\(chosen.count)")
    }

    private static func single(_ entry: Entry, view: ChatView, report: SweepReport) async -> Bool {
        view.store.newConversation()
        view.pendingImages = []
        view.pendingFiles = []
        switch entry.shot {
        case .none: break
        case .shape(let fixture):
            view.pendingImages = [PendingPicture(image: fixture.image(),
                                                 file: entry.cameraShot ? nil : fixture.file)]
        case .tag:
            view.pendingImages = [PendingPicture(image: DebugPriceProbe.tag(), file: nil)]
        case .note:
            view.pendingImages = [PendingPicture(image: ReceiptCard.receiptCard(
                fontSize: 46, text: "Reparatur der Werkbank\nKosten: 480 Euro\nTermin: Freitag"), file: nil)]
        }
        if let text = entry.fileText, let pending = DebugChainFixtures.attachedRTF(text, view: view) {
            view.pendingFiles = [pending]
        }
        let before = view.store.current?.messages.count ?? 0
        view.input = entry.sentence
        flowMark("KOMBO fall=\(entry.name) schnitt=\(entry.section) anhang_bild=\(!view.pendingImages.isEmpty) "
                 + "anhang_datei=\(!view.pendingFiles.isEmpty)")
        await view.send()
        view.pendingImages = []
        view.pendingFiles = []
        let answers = Array((view.store.current?.messages ?? []).dropFirst(before))
            .filter { $0.role == .assistant }
        var got = TurnArtifacts()
        answers.forEach { got.take($0) }
        let fehlt = entry.expects.filter { !$0.met(got) }.map { $0.name }
        if entry.marker != nil || got.appointments > 0 {
            await DebugChainFixtures.removeAppointments(
                refs: answers.compactMap { $0.calendarRef },
                markers: [entry.marker ?? "Gwen"], report: report)
        }
        report.add("KOMBO_\(entry.name)",
                   "ok=\(fehlt.isEmpty) fehlt=\(fehlt.isEmpty ? "keins" : fehlt.joined(separator: ",")) "
                   + "antworten=\(answers.count) text=\(got.text) bilder=\(got.pictures) "
                   + "galerie=\(got.gallery) orte=\(got.places) quellen=\(got.sources) "
                   + "preisrunden=\(got.priceRounds) termine=\(got.appointments)")
        for (index, answer) in answers.enumerated() {
            report.add("KOMBO_\(entry.name)_BLASE_\(index)", DebugChainFixtures.describe(answer))
        }
        return fehlt.isEmpty
    }
}
#endif
