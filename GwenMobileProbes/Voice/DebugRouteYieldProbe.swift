@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import AVFoundation
import UIKit

@MainActor
enum DebugRouteYieldProbe {
    static let settleSeconds = 4

    static func run(_ view: ChatView) async {
        let report = SweepReport(file: "route_yield.txt")
        let session = AVAudioSession.sharedInstance()
        let before = view.settings.voice.listenMode
        view.settings.voice.listenMode = true
        _ = await ProbeWait.until(20) { HeldMicrophone.shared.isLive && view.probeVoiceState == .waiting }
        report.add("START", state(view))
        let builtIn = session.availableInputs?.first { $0.portType == .builtInMic }
        await step("A_EINGANG_IPHONE", view: view, report: report) {
            try await ProbeAudioSession.setPreferredInput(builtIn)
        }
        await step("B_AUSGANG_LAUTSPRECHER", view: view, report: report) {
            try await ProbeAudioSession.overrideOutput(.speaker)
        }
        await step("C_ALLES_ZURUECK", view: view, report: report) {
            try await ProbeAudioSession.overrideOutput(.none)
            try await ProbeAudioSession.setPreferredInput(nil)
        }
        let without = RecordingSetup.handsFree.options.subtracting([.allowBluetoothHFP])
        await step("D_OHNE_BLUETOOTH", view: view, report: report) {
            try await ProbeAudioSession.setCategory(.playAndRecord, mode: session.mode, options: without)
        }
        await step("E_MIT_BLUETOOTH", view: view, report: report) {
            try await ProbeAudioSession.setCategory(.playAndRecord, mode: session.mode,
                                                    options: RecordingSetup.preferred[0].options)
        }
        view.settings.voice.listenMode = before
        report.add("ENDE", state(view))
        flowMark("WEGFREIGABE fertig")
    }

    private static func step(_ label: String, view: ChatView, report: SweepReport,
                             _ action: () async throws -> Void) async {
        var failure = "-"
        do { try await action() } catch { failure = "\((error as NSError).code)" }
        try? await Task.sleep(for: .seconds(settleSeconds))
        let counted = HeldMicrophone.shared.buffersDelivered
        try? await Task.sleep(for: .seconds(2))
        report.add(label, "fehler=\(failure) puffer_in_2s=\(HeldMicrophone.shared.buffersDelivered - counted) "
                   + state(view))
    }

    private static func state(_ view: ChatView) -> String {
        let session = AVAudioSession.sharedInstance()
        let inputs = (session.availableInputs ?? []).map(\.portType.rawValue).joined(separator: ",")
        return "mikro_an=\(HeldMicrophone.shared.isLive) stimme=\(view.probeVoiceState) hz=\(Int(session.sampleRate)) "
            + "optionen=\(session.categoryOptions.rawValue) verfuegbar=\(inputs) " + MicrophoneRoute.current()
    }

}
#endif
