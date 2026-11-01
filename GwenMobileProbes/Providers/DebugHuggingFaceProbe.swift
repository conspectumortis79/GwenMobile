@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import Foundation

@MainActor
enum DebugHuggingFaceProbe {
    static let reportFile = "huggingface_probe.txt"

    static func run() async {
        let report = SweepReport(file: reportFile)
        report.add("MARKE", "hfprobe-v1")
        report.add("SPEICHER", "phys=\(LocalMemory.physical) frei=\(LocalMemory.available) "
                   + "canHost4=\(LocalMemory.canHost(4_000_000_000))")
        await LocalModelStore.shared.searchHuggingFace()
        if let error = LocalModelStore.shared.huggingFaceError {
            report.add("FEHLER", error)
            return
        }
        let found = LocalModelStore.shared.huggingFace
        report.add("GEFUNDEN", "anzahl=\(found.count)")
        for choice in found {
            report.add("MODELL", "id=\(choice.id) params=\(choice.parameterBillions ?? -1) "
                       + "bytes=\(choice.bytes) vision=\(choice.vision) "
                       + "canHost=\(LocalMemory.canHost(choice.bytes)) "
                       + "canFit=\(LocalMemory.canFit(choice.bytes))")
        }
        let selected = found.filter { LocalMemory.canHost($0.bytes) }
        report.add("AUSWAHL", "anzahl=\(selected.count) ids=\(selected.map(\.id).joined(separator: ","))")
        report.add("ENDE", "ok")
    }
}
#endif
