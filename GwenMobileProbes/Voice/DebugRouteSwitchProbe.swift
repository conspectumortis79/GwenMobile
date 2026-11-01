@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import AVFoundation
import UIKit

@MainActor
enum DebugRouteSwitchProbe {
    static let rounds = ProbeRounds.maximum
    static let settleSeconds = 3

    static func run(_ view: ChatView) async {
        let report = SweepReport(file: "route_switch.txt")
        let session = AVAudioSession.sharedInstance()
        let microphone = HeldMicrophone.shared
        let before = view.settings.voice.listenMode
        view.settings.voice.listenMode = true
        let ready = await ProbeWait.until(20) { microphone.isLive && view.probeVoiceState == .waiting }
        let inputs = (session.availableInputs ?? []).map { "\($0.portType.rawValue)[\($0.portName)]" }
        report.add("START", "bereit=\(ready) eingaenge=\(inputs.joined(separator: ",")) "
                   + "hz=\(Int(session.sampleRate)) " + MicrophoneRoute.current(session))
        let builtIn = session.availableInputs?.first { $0.portType == .builtInMic }
        let external = session.availableInputs?.first { $0.portType != .builtInMic }
        for round in 1...rounds {
            await step("R\(round)_EINGEBAUT", prefer: builtIn, view: view, report: report)
            await step("R\(round)_EXTERN", prefer: external, view: view, report: report)
        }
        try? session.setPreferredInput(nil)
        view.settings.voice.listenMode = before
        report.add("ENDE", "mikro_an=\(microphone.isLive) stimme=\(view.probeVoiceState)")
        flowMark("WEGWECHSEL fertig")
    }

    private static func step(_ label: String, prefer port: AVAudioSessionPortDescription?, view: ChatView,
                             report: SweepReport) async {
        let session = AVAudioSession.sharedInstance()
        let microphone = HeldMicrophone.shared
        var failure = "-"
        do {
            try session.setPreferredInput(port)
        } catch {
            failure = "\((error as NSError).code)"
        }
        try? await Task.sleep(for: .seconds(settleSeconds))
        let counted = microphone.buffersDelivered
        try? await Task.sleep(for: .seconds(settleSeconds))
        let flowing = microphone.buffersDelivered - counted
        report.add(label, "ziel=\(port.map { $0.portType.rawValue } ?? "keins") fehler=\(failure) "
                   + "hz=\(Int(session.sampleRate)) puffer_in_\(settleSeconds)s=\(flowing) "
                   + "mikro_an=\(microphone.isLive) stimme=\(view.probeVoiceState) "
                   + MicrophoneRoute.current(session))
    }

}
#endif
