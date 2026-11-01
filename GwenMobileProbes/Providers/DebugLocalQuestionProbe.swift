@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import Foundation
import UIKit

@MainActor
enum DebugLocalQuestionProbe {
    static let reportFile = "local_question.txt"
    static let question = "Wann wurde die BRD gegründet?"

    static func run(_ view: ChatView) async {
        let report = SweepReport(file: reportFile)
        let settings = view.settings
        let installed = LocalModelFiles().installedIDs()
        report.add("MARKE", "localquestion-v1")
        report.add("INSTALLIERT", installed.joined(separator: ","))
        report.add("SPEICHER", "frei=\(LocalMemory.available) phys=\(LocalMemory.physical)")
        guard settings.provider == .local, settings.isConfigured, !settings.chatModel.isEmpty else {
            report.add("MODELL", "uebersprungen: provider=\(settings.provider.rawValue) "
                       + "konfiguriert=\(settings.isConfigured) chat=\(settings.chatModel)")
            report.add("ENDE", "ok")
            return
        }
        let model = settings.chatModel
        await LocalEngine.shared.unload()
        let before = await LocalEngine.shared.memoryReport()
        report.add("VORLAUF", "modell=\(model) frei=\(before.available) mlx_aktiv=\(before.mlxActive) "
                   + "mlx_peak=\(before.mlxPeak)")
        view.input = question
        report.add("FRAGE", question)
        view.probeStartSend()
        for round in 1...120 {
            try? await Task.sleep(for: .seconds(5))
            let memory = await LocalEngine.shared.memoryReport()
            let models = await LocalEngine.shared.modelSnapshot()
            let queue = await LocalEngine.shared.queueState()
            report.add("LAUF_\(round)", "in_flight=\(view.probeRunInFlight) streaming=\(view.probeStreaming) "
                       + "busy=\(view.probeBusy) geladen=\(models.loaded ?? "-") aktiv=\(memory.active) "
                       + "frei=\(memory.available) mlx_aktiv=\(memory.mlxActive) "
                       + "mlx_peak=\(memory.mlxPeak) mlx_cache=\(memory.mlxCache) "
                       + "queued=\(queue.queued) running=\(queue.running)")
            if !view.probeRunInFlight, !view.probeStreaming { break }
        }
        report.add("ALERTS", view.probeAlerts.map { $0.message }.joined(separator: " | "))
        let after = await LocalEngine.shared.memoryReport()
        let loadedAfter = await LocalEngine.shared.modelSnapshot().loaded
        report.add("NACHLAUF", "frei=\(after.available) mlx_aktiv=\(after.mlxActive) "
                   + "mlx_peak=\(after.mlxPeak) geladen=\(loadedAfter ?? "-")")
        report.add("LISTE_NACH", settings.profile(of: .local).availableModels.joined(separator: ","))
        report.add("ENDE", "ok")
    }
}
#endif
