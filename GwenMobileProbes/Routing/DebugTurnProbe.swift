@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import Foundation

@MainActor
enum DebugTurnProbe {
    private struct Turn {
        let sentence: String
        let expects: [TurnExpectation]
    }

    private struct Scenario {
        let name: String
        let marker: String?
        let turns: [Turn]
    }

    private static let scenarios: [Scenario] = [
        Scenario(name: "natalie_drei_aufgaben_original", marker: nil, turns: [
            Turn(sentence: "Wer ist Natalie Portman und dann bitte ein paar Bilder zeigen und dann bitte "
            + "das erste Bild, was du findest, wenn du gesucht hast, als Schwarz-Weiß-Bild machen",
            expects: [.text, .gallery, .exactly(1)]),
        ]),
        Scenario(name: "natalie_ein_satz_drei_aufgaben", marker: nil, turns: [
            Turn(sentence: "Wer ist Natalie Portman zeige mir Bilder dafür und das erste Bild bitte in "
            + "schwarz-weiß umwandeln",
            expects: [.text, .gallery, .exactly(1)]),
        ]),
        Scenario(name: "nachrichten_kriminalitaet_rate", marker: nil, turns: [
            Turn(sentence: "Zeig mir aktuelle Nachrichten aus Berlin.",
                 expects: [.text, .sources]),
            Turn(sentence: "Zeig mir davon nur alles, was mit Kriminalität zu tun hat.",
                 expects: [.text, .any(label: "krimin",
                                       list: ["krimin", "delikt", "straf", "diebstahl", "überfall"])]),
            Turn(sentence: "Wie aktuell ist die Kriminalitätsrate in Berlin?",
                 expects: [.text]),
        ]),
        Scenario(name: "natalie_portman_drei_runden", marker: nil, turns: [
            Turn(sentence: "Wie sieht Natalie Portman aus?", expects: [.gallery]),
            Turn(sentence: "Wie ist ihr richtiger Name?",
                 expects: [.text, .any(label: "geburtsname", list: ["hershlag", "herslag", "netta", "neta"])]),
            Turn(sentence: "Ändere das erste Bild davon in Schwarz-Weiß.", expects: [.exactly(1)]),
        ]),
        Scenario(name: "termin_banane_und_korrektur", marker: "Banane", turns: [
            Turn(sentence: "Erstelle einen Termin für morgen 11 Uhr mit dem Namen Banane.",
                 expects: [.appointment, .titleContains("Banane"), .lastStart(hour: 11)]),
            Turn(sentence: "Korrigiere den Termin: fange morgen um 15 Uhr an und nenne ihn Bananentreffen.",
                 expects: [.appointment, .titleContains("Bananentreffen"), .lastStart(hour: 15)]),
        ]),
    ]

    static func sweep(_ view: ChatView) async {
        let report = SweepReport(file: "turn_sweep.txt")
        report.add("KONFIG", "schluessel=\(view.settings.isConfigured) chat=\(view.settings.chatModel) "
                   + "vision=\(view.settings.visionModel) bild=\(view.settings.imageModel) "
                   + "erinnerte_bilder=\(ImagePolicy.rememberedPictures)")
        var passed = 0
        var total = 0
        for scenario in ProbeRounds.capped(scenarios) {
            view.store.newConversation()
            var refs: [CalendarRef] = []
            for (index, turn) in scenario.turns.enumerated() {
                total += 1
                let ok = await run(scenario, turn, round: index + 1, view: view,
                                  refs: &refs, report: report)
                passed += ok ? 1 : 0
            }
            if scenario.marker != nil || !refs.isEmpty {
                await DebugChainFixtures.removeAppointments(
                    refs: refs, markers: [scenario.marker ?? "Banane"], report: report)
            }
        }
        report.add("SUMME", "runden_ok=\(passed)/\(total)")
        flowLog.info("RUNDEN fertig ok=\(passed)/\(total)")
    }

    private static func run(_ scenario: Scenario, _ turn: Turn, round: Int, view: ChatView,
                            refs: inout [CalendarRef], report: SweepReport) async -> Bool {
        let before = view.store.current?.messages.count ?? 0
        view.input = turn.sentence
        flowMark("RUNDEN fall=\(scenario.name) runde=\(round)")
        await view.send()
        let answers = Array((view.store.current?.messages ?? []).dropFirst(before))
            .filter { $0.role == .assistant }
        var got = TurnArtifacts()
        answers.forEach { got.take($0) }
        refs.append(contentsOf: got.refs)
        let fehlt = turn.expects.filter { !$0.met(got) }.map { $0.name }
        report.add("RUNDEN_\(scenario.name)_r\(round)",
                   "ok=\(fehlt.isEmpty) fehlt=\(fehlt.isEmpty ? "keins" : fehlt.joined(separator: ",")) "
                   + "antworten=\(answers.count) text=\(got.text) bilder=\(got.pictures) "
                   + "galerie=\(got.gallery) orte=\(got.places) quellen=\(got.sources) "
                   + "preise=\(got.price) termine=\(got.appointments)")
        report.add("RUNDEN_\(scenario.name)_r\(round)_FRAGE", TextLine.oneLine(turn.sentence, limit: 110))
        for (index, answer) in answers.enumerated() {
            report.add("RUNDEN_\(scenario.name)_r\(round)_BLASE_\(index)",
                       DebugChainFixtures.describe(answer))
        }
        return fehlt.isEmpty
    }
}
#endif
