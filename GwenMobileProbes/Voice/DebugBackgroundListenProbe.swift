@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import AVFoundation
import UIKit

@MainActor
enum DebugBackgroundListenProbe {
    static let waitForSwitch = 20
    static let pulseSeconds = 10
    static let settleSeconds = 2

    static func run(_ view: ChatView) async {
        let report = SweepReport(file: "background_listen.txt")
        let settings = view.settings
        let before = (listen: settings.voice.listenMode, wake: settings.voice.wakeWord, stop: settings.voice.stopWord)
        settings.voice.wakeWord = ""
        settings.voice.stopWord = ""
        settings.voice.listenMode = true
        view.probeAbortVoice()
        report.add("START", "vorlesen=\(view.settings.voice.speakAnswers) weck=\(view.settings.spokenWake) "
                   + "stopp=\(view.settings.spokenStop) " + snapshot(view))
        let pulse = Task { await sample(view, into: report) }
        let ready = await ProbeWait.until(10) { view.probeVoiceState == .waiting }
        report.add("VORNE_BEREIT", "bereit=\(ready) " + snapshot(view))
        let away = await ProbeWait.until(waitForSwitch) { UIApplication.shared.applicationState == .background }
        report.add("WECHSEL", "hintergrund=\(away) " + snapshot(view))
        if away {
            try? await Task.sleep(for: .seconds(2))
            report.add("HINTEN_2S", snapshot(view))
            await freshStart(view, report: report)
        }
        flowMark("ZUHOERPROBE hintergrund fertig")
        let back = await ProbeWait.until(waitForSwitch) { UIApplication.shared.applicationState == .active }
        try? await Task.sleep(for: .seconds(2))
        report.add("ZURUECK", "vorne=\(back) " + snapshot(view))
        pulse.cancel()
        report.add("ENDE", answers(view))
        settings.voice.listenMode = before.listen
        settings.voice.wakeWord = before.wake
        settings.voice.stopWord = before.stop
        view.probeAbortVoice()
        flowMark("ZUHOERPROBE fertig")
    }

    private static func freshStart(_ view: ChatView, report: SweepReport) async {
        let microphone = HeldMicrophone.shared
        view.settings.voice.listenMode = false
        let off = await ProbeWait.until(10) { !microphone.isLive }
        try? await Task.sleep(for: .seconds(settleSeconds))
        let session = AVAudioSession.sharedInstance()
        report.add("HINTEN_AUS", "mikro_aus=\(off) kategorie=\(session.category.rawValue) "
                   + "aufnahmen=\(AudioRound.capturing.current) " + snapshot(view))
        if off {
            let counted = microphone.buffersDelivered
            do {
                try await microphone.start { _ in }
                try? await Task.sleep(for: .seconds(settleSeconds))
                report.add("HINTEN_NEUSTART", "gestartet=true puffer_in_\(settleSeconds)s="
                           + "\(microphone.buffersDelivered - counted)")
            } catch {
                report.add("HINTEN_NEUSTART", "gestartet=false code=\((error as NSError).code) "
                           + "text=\(TextLine.oneLine(error.localizedDescription, limit: 120))")
            }
            microphone.stop()
        }
        view.settings.voice.listenMode = true
        try? await Task.sleep(for: .seconds(settleSeconds))
        report.add("HINTEN_WIEDER_AN", snapshot(view))
    }

    private static func sample(_ view: ChatView, into report: SweepReport) async {
        var last = ""
        var second = 0
        while !Task.isCancelled {
            let line = snapshot(view)
            if line != last {
                report.add("T\(second)", line)
                last = line
            }
            if second % pulseSeconds == 0 {
                report.add("PULS\(second)", "puffer=\(HeldMicrophone.shared.buffersDelivered) "
                           + "koerper=\(RenderStats.chatBody.current)")
            }
            try? await Task.sleep(for: .seconds(1))
            second += 1
        }
    }

    static func snapshot(_ view: ChatView) -> String {
        let microphone = HeldMicrophone.shared
        return "app=\(appState) stimme=\(view.probeVoiceState) mikro_an=\(microphone.isLive) "
            + "gehalten=\(microphone.isHeld) spricht=\(view.probeSpeaking) "
            + "nachrichten=\(view.store.current?.messages.count ?? 0) " + MicrophoneRoute.current()
    }

    private static func answers(_ view: ChatView) -> String {
        (view.store.current?.messages ?? []).suffix(6)
            .map { "\($0.role == .user ? "F" : "A"):\(TextLine.oneLine($0.text, limit: 90))" }
            .joined(separator: " | ")
    }

    static var appState: String {
        switch UIApplication.shared.applicationState {
        case .active: return "vorne"
        case .inactive: return "inaktiv"
        case .background: return "hintergrund"
        @unknown default: return "unbekannt"
        }
    }
}
#endif
