@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import Foundation

@MainActor
enum DebugAppStatusProbe {
    private static let sentence = "Bitte prüfe den aktuellen Status von GwenMobile und sag mir, ob alles rund läuft."

    private static var summaryMarkers: [String] {
        let counted = [L.t("app_status_summary_attention"), L.t("app_status_summary_problem")]
            .compactMap { $0.components(separatedBy: "%d").first }
            .filter { !$0.isEmpty }
        return [L.t("app_status_summary_ok")] + counted
    }

    static func run(_ view: ChatView) async {
        let report = SweepReport(file: "app_status.txt")
        let stale = view.store.conversations.filter { conversation in
            conversation.messages.contains { $0.role == .user && $0.text.contains("Bitte prüfe den aktuellen Status von GwenMobile") }
                && conversation.messages.contains { $0.role == .assistant && $0.text.contains(L.t("app_status_title")) }
        }
        for conversation in stale { _ = view.store.removeConversation(conversation.id) }
        let known = Set(view.store.conversations.map(\.id))
        let previous = view.store.currentID
        report.add("VORAB", "alte_status_gespraeche=\(stale.count)")
        report.add("FRAGE", sentence)
        let answers = await DebugFeatureProbe.freshAsk(view, sentence,
                                                       log: "APPSTATUS frage", resetPlan: true)
        let plan = view.probeLastPlan
        let routed = plan?.actions.contains { $0.stepKind == .status } ?? false
        var artifacts = TurnArtifacts()
        answers.forEach { artifacts.take($0) }
        let title = L.t("app_status_title")
        let summary = Self.summaryMarkers.contains { artifacts.fullText.contains($0) }
        let rows = artifacts.fullText.contains(L.t("app_status_label_app"))
            && artifacts.fullText.contains(L.t("api_key"))
            && artifacts.fullText.contains(L.t("storage"))
        let ok = routed && summary && rows && artifacts.answers == 1
        report.add("PLAN", "\(plan?.traceLine ?? "keine") status=\(routed)")
        report.add("ANTWORT", "ok=\(ok) blasen=\(artifacts.answers) zeichen=\(artifacts.text) "
                   + "titel=\(artifacts.fullText.contains(title)) summary=\(summary) zeilen=\(rows)")
        report.add("TEXT", TextLine.oneLine(artifacts.fullText, limit: 700))
        let removed = DebugFeatureProbe.cleanUpProbeConversations(view, keeping: known, restore: previous)
        report.add("AUFRAEUMEN", "entfernt=\(removed)")
    }
}
#endif
