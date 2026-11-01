@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import Foundation

@MainActor
enum DebugStepProbe {
    private struct Entry {
        let name: String
        let sentence: String
        let fixture: PictureProbe.Fixture?
        let appointment: String?
        var cameraShot = false
        var fileText: String?
        var expects: [TurnExpectation] = []
    }

    private static let entries: [Entry] = [
        Entry(name: "beschreibung_und_schwarzweiss",
              sentence: "Was siehst du auf dem Bild? Ändere das Bild bitte in Schwarz-Weiß.",
              fixture: PictureProbe.star, appointment: nil, expects: [.exactly(1), .noGallery]),
        Entry(name: "markt_und_oeffnungszeiten",
              sentence: "Wo ist der nächste Kaufland-Markt? Zeig mir bitte auch die Öffnungszeiten.",
              fixture: nil, appointment: nil, expects: [.places, .sources, .exactly(0), .bubbles(1)]),
        Entry(name: "nachrichten_und_termin",
              sentence: "Zeig mir aktuell Nachrichten aus Berlin und mache mir auch einen Termin für "
              + "morgen 11 Uhr für 2 Stunden mit dem Namen Blubb.",
              fixture: nil, appointment: "Blubb",
              expects: [.sources, .appointments(1), .titleContains("Blubb"), .exactly(0), .noGallery]),
        Entry(name: "galerie_und_termin",
              sentence: "Such mir Bilder vom Nordlicht und trag für morgen 9 Uhr einen Termin "
              + "GwenNordlicht ein.",
              fixture: nil, appointment: "GwenNordlicht",
              expects: [.gallery, .appointments(1), .titleContains("GwenNordlicht"), .exactly(0)]),
        Entry(name: "beschreibung_und_galerie",
              sentence: "Was ist auf dem Bild zu sehen? Such mir außerdem Bilder davon.",
              fixture: PictureProbe.circle, appointment: nil, expects: [.gallery, .exactly(0)]),
        Entry(name: "kamera_drei_anweisungen",
              sentence: "Was ist das für eine Szene? Mach das Bild schwarz-weiß und suche danach ein Bild "
              + "von demselben Motiv.",
              fixture: PictureProbe.square, appointment: nil, cameraShot: true,
              expects: [.exactly(1), .gallery]),
        Entry(name: "datei_fass_und_zwei_sprachen",
              sentence: "Fasse zusammen, was in der Datei steht, übersetze die Zusammenfassung ins "
              + "Englische und zusätzlich ins Polnische.",
              fixture: nil, appointment: nil,
              fileText: "Punkt 4.2: Für den Ausbau des Lagers sind 85.000 Euro vorgesehen. "
              + "Termin: nächste Woche, 03.07. Der Rat stimmt am Freitag ab.",
              expects: [.any(label: "englisch", list: ["warehouse", "friday", "council"]),
                        .any(label: "polnisch", list: ["piątek", "lipca", "przyszłym", "tydzień", "magazyn"]),
                        .exactly(0)]),
        Entry(name: "nurfrage_ohne_zweiten_wunsch",
              sentence: "Wer ist Michael Jackson?",
              fixture: nil, appointment: nil, expects: [.text, .exactly(0), .noGallery, .bubbles(1)]),
        Entry(name: "nurmaierei_ohne_zweiten_wunsch",
              sentence: "Male einen Sonnenuntergang am Meer.",
              fixture: nil, appointment: nil, expects: [.exactly(1), .bubbles(1)]),
        Entry(name: "nurgalerie_ohne_zweiten_wunsch",
              sentence: "Zeig mir Bilder vom Eiffelturm.",
              fixture: nil, appointment: nil, expects: [.gallery, .exactly(0), .bubbles(1)]),
        Entry(name: "dreiwuensche",
              sentence: "Such mir Bilder vom Nordlicht, bring mir Nachrichten aus Berlin und mach "
              + "einen Termin GwenDrei für morgen 14 Uhr.",
              fixture: nil, appointment: "GwenDrei",
              expects: [.gallery, .sources, .appointments(1), .titleContains("GwenDrei"), .exactly(0)]),
        Entry(name: "vierwuensche",
              sentence: "Such mir Bilder vom Nordlicht, zeig mir die nächsten Supermärkte, bring mir "
              + "Nachrichten aus Berlin und mach einen Termin GwenKette für morgen 16 Uhr.",
              fixture: nil, appointment: "GwenKette",
              expects: [.gallery, .places, .sources, .appointments(1), .titleContains("GwenKette"), .exactly(0)]),
        Entry(name: "rueckbezug_auf_eigenes_bild",
              sentence: "Male einen roten Ball auf weißem Grund. Mach das neue Bild danach schwarz-weiß.",
              fixture: nil, appointment: nil, expects: [.exactly(2)]),
    ]

    static func sweep(_ view: ChatView) async {
        let report = SweepReport(file: "step_sweep.txt")
        PictureProbe.materialise(in: view.store.media)
        report.add("KONFIG", "schluessel=\(view.settings.isConfigured) chat=\(view.settings.chatModel) "
                   + "bild=\(view.settings.imageModel) vision=\(view.settings.visionModel) "
                   + "ortung=\(view.store.current != nil)")
        var passed = 0
        let batch = ProbeRounds.capped(entries)
        for entry in batch {
            passed += await run(entry, view: view, report: report) ? 1 : 0
        }
        report.add("SUMME", "ok=\(passed)/\(batch.count)")
        flowLog.info("SCHRITTE fertig ok=\(passed)/\(batch.count)")
    }

    private static func run(_ entry: Entry, view: ChatView, report: SweepReport) async -> Bool {
        view.store.newConversation()
        view.pendingImages = []
        view.pendingFiles = []
        if let fixture = entry.fixture {
            view.pendingImages = [PendingPicture(image: fixture.image(),
                                                 file: entry.cameraShot ? nil : fixture.file)]
        }
        if let text = entry.fileText, let pending = DebugChainFixtures.attachedRTF(text, view: view) {
            view.pendingFiles = [pending]
        }
        let before = view.store.current?.messages.count ?? 0
        view.input = entry.sentence
        await view.send()
        view.pendingImages = []
        view.pendingFiles = []
        let answers = (view.store.current?.messages ?? []).dropFirst(before).filter { $0.role == .assistant }
        let withText = answers.filter { !$0.text.trimmed.isEmpty }
        let pictures = answers.reduce(0) { $0 + ($1.outImages?.count ?? 0) }
        let gallery = answers.contains { $0.hasGallery }
        let places = answers.contains { !$0.allPlaces.isEmpty }
        let sources = answers.contains { !($0.sources ?? []).isEmpty }
        let appointment = answers.contains { $0.calendarRef != nil }
        let merged = answers.contains { answer in
            !answer.text.trimmed.isEmpty
                && ((answer.outImages?.isEmpty == false) || answer.hasGallery
                    || !answer.allPlaces.isEmpty || answer.calendarRef != nil)
        }
        var got = TurnArtifacts()
        answers.forEach { got.take($0) }
        let fehlt = entry.expects.filter { !$0.met(got) }.map(\.name)
        report.add("FALL_\(entry.name)",
                   "ok=\(fehlt.isEmpty) fehlt=\(fehlt.isEmpty ? "keins" : fehlt.joined(separator: ",")) "
                   + "antworten=\(answers.count) mit_text=\(withText.count) bilder=\(pictures) "
                   + "galerie=\(gallery) orte=\(places) quellen=\(sources) termin=\(appointment) "
                   + "eine_antwort=\(merged)")
        report.add("FALL_\(entry.name)_SATZ", TextLine.oneLine(entry.sentence, limit: 110))
        for (index, answer) in answers.enumerated() {
            report.add("FALL_\(entry.name)_BLASE_\(index)", DebugChainFixtures.describe(answer))
        }
        if entry.appointment != nil || answers.contains(where: { $0.calendarRef != nil }) {
            await DebugChainFixtures.removeAppointments(
                refs: answers.compactMap { $0.calendarRef },
                markers: entry.appointment.map { [$0] } ?? [], report: report)
        }
        return fehlt.isEmpty
    }
}
#endif
