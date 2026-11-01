@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import UIKit

@MainActor
enum DebugListenRouteProbe {
    static let seconds = 300
    static let markerName = "listen_release"

    static func run(_ view: ChatView) async {
        let report = SweepReport(file: "listen_route.txt")
        let marker = StoragePaths().documents.appendingPathComponent(markerName)
        DebugReleaseFlag.listen.consume()
        try? FileManager.default.removeItem(at: marker)
        let before = view.settings.voice.listenMode
        view.settings.voice.listenMode = true
        report.add("START", "weck=\(view.settings.spokenWake) stopp=\(view.settings.spokenStop) "
                   + "sekunden=\(seconds)")
        var last = ""
        var question = latestQuestion(view)
        var wakes = 0
        var wasRecording = false
        var releasedEarly = false
        for second in 0..<seconds {
            if DebugReleaseFlag.listen.isRequested || FileManager.default.fileExists(atPath: marker.path) {
                releasedEarly = true
                break
            }
            let line = DebugBackgroundListenProbe.snapshot(view)
            if line != last {
                report.add("T\(second)", line)
                last = line
            }
            let recording = view.probeVoiceState == .recording
            if recording, !wasRecording {
                wakes += 1
                report.add("WECKWORT_T\(second)", "nummer=\(wakes) gehoert=\(String(view.probeHeard.suffix(120)))")
            }
            wasRecording = recording
            let asked = latestQuestion(view)
            if asked != question {
                report.add("ANFRAGE_T\(second)", TextLine.oneLine(asked ?? "-", limit: 120))
                question = asked
            }
            try? await Task.sleep(for: .seconds(1))
        }
        report.add("ENDE", "weckwoerter=\(wakes) vorzeitig=\(releasedEarly) "
                   + DebugBackgroundListenProbe.snapshot(view))
        DebugReleaseFlag.listen.consume()
        try? FileManager.default.removeItem(at: marker)
        view.settings.voice.listenMode = before
        flowMark("ZUHOERWEG fertig")
    }

    private static func latestQuestion(_ view: ChatView) -> String? {
        view.store.current?.messages.last(where: { $0.role == .user })?.text
    }
}
#endif
