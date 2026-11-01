@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import AVFoundation
import Foundation

@MainActor
enum DebugSoundProbe {
    static let sampleNames = ["DictationBegin", "DictationConfirm", "jbl begin", "jbl confirm", "Tink", "Bloom"]

    static func catalog(_ view: ChatView) async {
        let report = SweepReport(file: "sound_catalog.txt")
        for root in SystemSoundCatalog.liveRoots {
            let readable = FileManager.default.isReadableFile(atPath: root)
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: root))?.count ?? -1
            report.add("WURZEL", "pfad=\(root) lesbar=\(readable) eintraege=\(entries)")
        }
        guard let catalog = SystemSoundCatalog.live() else {
            report.add("KATALOG", "keine lesbare wurzel")
            flowLog.info("TONKATALOG fertig")
            return
        }
        let started = ContinuousClock.now
        let sounds = await Offload.orNil { catalog.sounds() } ?? []
        let folders = Dictionary(grouping: sounds, by: \.folder).mapValues(\.count)
        report.add("KATALOG", "wurzel=\(catalog.root.path) toene=\(sounds.count) "
                   + "ordner=\(folders.sorted { $0.key < $1.key }.map { "\($0.key.isEmpty ? "-" : $0.key):\($0.value)" }.joined(separator: ",")) "
                   + "ms=\(msOf(started.duration(to: .now)))")
        var loaded = 0
        for sound in sounds where (try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: sound.path))) != nil {
            loaded += 1
        }
        report.add("LADBAR", "\(loaded)/\(sounds.count)")
        for wanted in sampleNames {
            let hit = sounds.first { $0.name.caseInsensitiveCompare(wanted) == .orderedSame }
            let player = hit.flatMap { try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: $0.path)) }
            report.add("PROBE_\(wanted.replacingOccurrences(of: " ", with: "_"))",
                       "gefunden=\(hit != nil) ordner=\(hit?.folder ?? "-") "
                       + "dauer_ms=\(player.map { Int($0.duration * 1000) } ?? -1)")
        }
        report.add("EINSTELLUNG", "weckton=sprachansage "
                   + "sendeton=\(label(view.settings.voice.sentSound))")
        flowLog.info("TONKATALOG fertig")
    }

    private static func label(_ path: String) -> String {
        path.isEmpty ? "gwenmobile" : SystemSoundCatalog.name(ofPath: path)
    }
}
#endif
