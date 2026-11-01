@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import EventKit
import Foundation

@MainActor
enum DebugCalendarAccessProbe {
    private struct Entry {
        let name: String
        let sentence: String
        let marker: String
        var expects: [TurnExpectation] = []
    }

    private static let entries: [Entry] = [
        Entry(name: "kurz_kontrolle",
              sentence: "Erstelle mir einen Termin für morgen 16:30 Uhr mit dem Namen GwenKurz.",
              marker: "GwenKurz", expects: [.appointment, .noWarning]),
        Entry(name: "vier_aufgaben_mit_termin",
              sentence: "Suche mir den günstigsten Mac Studio, zeige mir Bilder vom Mac Studio, erstelle "
              + "mir ein Bild eines Mac Studio und erstelle mir einen Termin für morgen 17 Uhr mit dem "
              + "Namen GwenVier.",
              marker: "GwenVier", expects: [.appointment, .noWarning]),
        Entry(name: "legitimes_update_in_der_kette",
              sentence: "Erstelle mir einen Termin für morgen 9 Uhr mit dem Namen GwenErst und verschiebe "
              + "GwenErst auf 10 Uhr.",
              marker: "GwenErst", expects: [.appointments(2), .titleContains("GwenErst"), .lastStart(hour: 10),
                                            .noWarning]),
        Entry(name: "natalie_vier_aufgaben",
              sentence: "Wer ist Natalie Portman? Hast du Bilder, wie sie aussieht? Erstelle mir auch ein "
              + "Comic-Bild von ihr. Zudem bitte noch den Termin für morgen 11 Uhr anlegen mit dem Namen "
              + "LLL.",
              marker: "LLL", expects: [.text, .gallery, .exactly(1), .appointment]),
        Entry(name: "drei_aufgaben_termin_letzt",
              sentence: "Zeige mir Bilder vom Mac Studio, erstelle mir ein Bild eines Mac Studio und "
              + "erstelle mir einen Termin für morgen 18 Uhr mit dem Namen GwenDrei.",
              marker: "GwenDrei", expects: [.appointment, .noWarning]),
    ]

    static func sweep(_ view: ChatView) async {
        let report = SweepReport(file: "calendar_access.txt")
        PictureProbe.materialise(in: view.store.media)
        report.add("STATUS", zugriff() + " service_has_access=\(CalendarService.hasAccess) "
                   + "kalender=\(CalendarService.writableCalendarCount) "
                   + "schluessel=\(view.settings.isConfigured)")
        for entry in ProbeRounds.capped(entries) {
            await run(entry, view: view, report: report)
        }
        report.add("STATUS_NACHHER", zugriff() + " service_has_access=\(CalendarService.hasAccess)")
        flowLog.info("KALENDERZUGRIFF fertig")
    }

    private static func zugriff() -> String {
        "status=\(EKEventStore.authorizationStatus(for: .event).rawValue)"
    }

    private static func run(_ entry: Entry, view: ChatView, report: SweepReport) async {
        let answers = await DebugFeatureProbe.freshAsk(view, entry.sentence,
                                                       log: "ZUGRIFF fall=\(entry.name)")
        var got = TurnArtifacts()
        answers.forEach { got.take($0) }
        let entschuldigung = got.fullText.lowercased().contains("keinen zugriff")
            || got.fullText.lowercased().contains("kein zugriff")
        let fehlt = entry.expects.filter { !$0.met(got) }.map { $0.name }
        report.add("ZUGRIFF_\(entry.name)",
                   "ok=\(fehlt.isEmpty) fehlt=\(fehlt.isEmpty ? "keins" : fehlt.joined(separator: ",")) "
                   + "termine=\(got.appointments) antworten=\(answers.count) text=\(got.text) "
                   + "bilder=\(got.pictures) galerie=\(got.gallery) preisrunden=\(got.priceRounds) "
                   + "modell_sagt_keinen_zugriff=\(entschuldigung)")
        report.add("ZUGRIFF_\(entry.name)_ENDE",
                   TextLine.oneLine(String(got.fullText.suffix(150)), limit: 170))
        await DebugChainFixtures.removeAppointments(
            refs: answers.compactMap { $0.calendarRef }, markers: [entry.marker], report: report)
    }
}
#endif
