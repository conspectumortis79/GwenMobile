@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import UIKit

@MainActor
enum DebugListenButtonProbe {
    static func run(_ view: ChatView) async {
        let report = SweepReport(file: "listen_button.txt")
        let before = view.settings.voice.listenMode
        view.settings.voice.listenMode = false
        try? await Task.sleep(for: .milliseconds(1200))
        shot(view, "aus", report: report)
        view.probeToggleListenMode()
        try? await Task.sleep(for: .milliseconds(600))
        shot(view, "an", report: report)
        await DebugVoiceProbe.settingsShots(view)
        report.add("EINSTELLUNGEN", "zuhoermodus=\(view.settings.voice.listenMode)")
        try? await Task.sleep(for: .milliseconds(800))
        view.probeToggleListenMode()
        try? await Task.sleep(for: .milliseconds(600))
        shot(view, "wieder_aus", report: report)
        view.settings.voice.listenMode = before
        flowMark("ZUHOERKNOPF fertig")
    }

    private static func shot(_ view: ChatView, _ label: String, report: SweepReport) {
        guard let window = Presenter.windowRootViewController?.view?.window else {
            report.add(label, "kein fenster")
            return
        }
        report.add(label, "zuhoermodus=\(view.settings.voice.listenMode) stimme=\(view.probeVoiceState) "
                   + ViewerProbe.snapshot(window, named: "listen_button_\(label).jpg", scale: window.screen.scale))
    }
}
#endif
