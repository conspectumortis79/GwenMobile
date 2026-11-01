@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import Foundation

@MainActor
enum DebugHistoryProbe {
    static func routing() async {
        let report = SweepReport(file: "history_route.txt")
        let erase = ToolRouter.map(name: ToolRouter.historyTool, arguments: "{}")
        report.add("ROUTE", describe(erase))
        let ignored = ToolRouter.map(name: ToolRouter.historyTool, arguments: #"{"scope":"current"}"#)
        report.add("SCOPE_IGNORIERT", describe(ignored))
        let plan = SendPlan.forming([erase].compactMap { $0 })
        report.add("PLAN", "\(plan.traceLine) schritte=\(plan.actions.count) eine_antwort=\(plan.merges)")
        let block = ToolRouter.systemBlock(now: "2026-10-04 16:20", context: SendContext(), transcript: "",
                                           eraseHistoryWord: "Verlauf löschen")
        report.add("PHRASE", block.contains("Verlauf löschen") ? "im systemblock" : "fehlt")
        let signals = VoiceSignals(wake: "hey gwen", stop: "senden", cancel: "abbrechen",
                                   newChat: "neuer chat", listenOff: "zuhören aus")
        let local = VoiceCommand.command(in: "Verlauf löschen", signals: signals)
        report.add("KEIN_SIGNAL", local == nil ? "kein lokaler befehl" : "lokal abgefangen")
        let other = VoiceCommand.command(in: "neuer chat", signals: signals)
        report.add("NEUER_CHAT", other.map(String.init(describing:)) ?? "kein lokaler befehl")
        flowLog.info("VERLAUFROUTING fertig")
    }

    private static func describe(_ decision: ToolDecision?) -> String {
        guard let decision else { return "kein aufruf" }
        return decision.route == .history ? "route=verlauf(alle)" : decision.stepKind.rawValue
    }
}
#endif
