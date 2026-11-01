@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import Foundation

@MainActor
enum DebugReadAloudProbe {
    private struct RouteCase: RouteSweep.KindedCase {
        let sentence: String
        let kind: SendStepKind
        var enabled: Bool?
    }

    private static let routeCases = [
        RouteCase(sentence: "Schalte das Vorlesen ein", kind: .readAloud, enabled: true),
        RouteCase(sentence: "Ab jetzt sollst du mir immer vorlesen", kind: .readAloud, enabled: true),
        RouteCase(sentence: "Mach das Vorlesen aus", kind: .readAloud, enabled: false),
        RouteCase(sentence: "Lies mir die Antwort noch einmal vor", kind: .readAnswer),
        RouteCase(sentence: "Read that answer to me", kind: .readAnswer),
        RouteCase(sentence: "Spiel Musik", kind: .music),
        RouteCase(sentence: "Wie spät ist es?", kind: .clock),
    ]

    static func routing(_ view: ChatView) async {
        await RouteSweep.routeAllKinded(routeCases, file: "read_aloud_route.txt", view: view,
                                        log: "VORLESENROUTING fertig", fits: fitting, detail: describe)
    }

    private static func fitting(_ item: RouteCase, plan: SendPlan) -> Bool {
        guard plan.primary.stepKind == item.kind else { return false }
        guard item.kind == .readAloud else { return true }
        guard case .readAloud(let request) = plan.primary.route else { return false }
        return request.enabled == item.enabled
    }

    private static func describe(_ plan: SendPlan) -> String {
        switch plan.primary.route {
        case .readAloud(let request): return "vorlesen:\(request.enabled ? "an" : "aus")"
        case .readAnswer: return "antwort_vorlesen"
        default: return plan.traceLine
        }
    }

    static func flow(_ view: ChatView) async {
        let report = SweepReport(file: "read_aloud_flow.txt")
        let before = view.settings.voice.speakAnswers
        let known = Set(view.store.conversations.map(\.id))
        let previous = view.store.currentID
        view.settings.voice.speakAnswers = false
        report.add("KONFIG", "vorher=\(before) schluessel=\(view.settings.isConfigured)")
        let on = await view.ask("Schalte das Vorlesen ein", fresh: true)
        let turnedOn = view.settings.voice.speakAnswers
        let off = await view.ask("Mach das Vorlesen wieder aus", fresh: true)
        let turnedOff = !view.settings.voice.speakAnswers
        let onWord = TextFolding.fold(on?.text ?? "").contains("vorlesen")
        let offWord = TextFolding.fold(off?.text ?? "").contains("vorlesen")
        report.add("VORLESEN", "an=\(turnedOn) aus=\(turnedOff) antwort_an=\(onWord) antwort_aus=\(offWord) "
                   + "antwort_an_text=\(TextLine.oneLine(on?.text ?? "", limit: 120))")
        _ = await view.ask("Was ist die Hauptstadt von Frankreich?", fresh: true)
        let read = await view.ask("Lies mir die Antwort vor", fresh: false)
        var speaking = view.probeSpeaking
        var waited = 0
        while !speaking, waited < 12 {
            try? await Task.sleep(for: .milliseconds(250))
            speaking = view.probeSpeaking
            waited += 1
        }
        let stillOff = !view.settings.voice.speakAnswers
        let readWord = TextFolding.fold(read?.text ?? "").contains("letzte antwort")
        report.add("ANTWORT_VORLESEN", "spricht=\(speaking) vorlesen_aus=\(stillOff) antwort=\(readWord) "
                   + "text=\(TextLine.oneLine(read?.text ?? "", limit: 120))")
        view.settings.voice.speakAnswers = before
        let removed = DebugFeatureProbe.cleanUpProbeConversations(view, keeping: known, restore: previous)
        report.add("AUFRAEUMEN", "probe_chats_entfernt=\(removed) chats=\(view.store.conversations.count) "
                   + "vorlesen_zurueck=\(view.settings.voice.speakAnswers == before)")
        let flip = turnedOn && turnedOff && onWord && offWord
        let readOut = speaking && stillOff && readWord
        report.add("SUMME", "richtig=\((flip ? 1 : 0) + (readOut ? 1 : 0))/2")
        flowLog.info("VORLESENABLAUF fertig")
    }
}
#endif
