#if DEBUG
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import Foundation

@MainActor
enum ModelPickProbe {
    static let reportFile = "model_pick.txt"

    static func run(_ view: ChatView) async {
        let report = SweepReport(file: reportFile)
        let settings = view.settings
        let model = settings.chatModel.trimmed
        guard settings.isConfigured else {
            report.add("ABBRUCH", "kein anbieter konfiguriert")
            return
        }
        guard !model.isEmpty else {
            report.add("ABBRUCH", "kein modell gewaehlt")
            return
        }
        report.add("KONFIG", "anbieter=\(settings.provider.rawValue) chat=\(model) "
                   + "modelle=\(settings.availableModels.count) modus=nur_aktuelles_modell")
        let result = await benchmark(view)
        report.add("MODELL", "\(model) richtig=\(result.right)/\(DebugReminderProbe.flowSentences.count) "
                   + "fehler=\(result.failures.map(String.init).joined(separator: ",")) ms=\(result.ms)")
        report.add("HINWEIS", "keine modellwechsel, konfiguration unveraendert")
        flowLog.info("MODELLAUSWAHL fertig ohne aenderung")
    }

    private static func benchmark(_ view: ChatView) async -> (right: Int, failures: [Int], ms: Int) {
        let store = ProbeReminderStore()
        let known = Set(view.store.conversations.map(\.id))
        let previous = view.store.currentID
        view.reminderDesk.stand(in: store, places: ProbePlaceLookup())
        let started = ContinuousClock.now
        var right = 0
        var failures: [Int] = []
        for (index, sentence) in DebugReminderProbe.flowSentences.enumerated() {
            let answer = await view.ask(sentence, fresh: true)
            if DebugReminderProbe.flowFits(index, store: store, answer: answer) {
                right += 1
            } else {
                failures.append(index + 1)
            }
        }
        let ms = msOf(started.duration(to: .now))
        view.reminderDesk.restore()
        _ = DebugFeatureProbe.cleanUpProbeConversations(view, keeping: known, restore: previous)
        return (right, failures, ms)
    }
}
#endif
#endif
