@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

#if DEBUG
import GwenMobileKit
#endif

extension ChatView {
    #if DEBUG
    func attachScrollProxy(_ proxy: ScrollViewProxy) {
        scrollProxy = proxy
    }

    func startFlowTest() {
        dispatchFlowTest(testCmd)
    }

    var probeBusyLabel: String { busy.label }

    var probeVoiceState: VoiceTranscriber.State { voice.state }

    var probeSourceChecks: Set<UUID> { sourceChecks }

    var probeRecorderActive: Bool { voice.probeRecorderActive }

    var probeSpeaking: Bool { speech.isSpeaking }

    var probeHeard: String { voice.heardSoFar }

    var probeMicrophoneHeld: Bool { microphone.isHeld }

    func probeHandle(_ command: SpokenCommand) { perform(command) }

    func probeToggleListenMode() { toggleListenMode() }

    func probeAbortVoice() { abortVoice() }

    var probeAlerts: [L.FriendlyError] { alerts }

    var probeChainRunning: Bool { chainRun.isRunning }

    func probeStopChain() { chainRun.requestStop() }

    func probeStartSend() { startSend() }

    func probeStopRun() { stopRun() }

    var probeRunInFlight: Bool { runTask != nil }

    var probeBusy: Bool { busy.isBusy }

    var probeStreaming: Bool { isStreaming }

    var probeStreamedChars: Int { streamText.count }

    func probeRaise(_ alert: L.FriendlyError) { queueAlert(alert) }

    func probeDismissAlert() { dismissAlert() }

    func dispatchFlowTest(_ name: String) {
        guard !name.isEmpty else { return }
        if name == "shotrelease" {
            DebugReleaseFlag.shot.request()
            flowMark("FLOWTEST shotrelease")
            return
        }
        if name == "listenrelease" {
            DebugReleaseFlag.listen.request()
            flowMark("FLOWTEST listenrelease")
            return
        }
        guard !testRunning else { return }
        testRunning = true
        flowMark("FLOWTEST dispatched cmd=\(name)")
        let desk = callDesk
        let music = musicDesk
        let messages = messageDesk
        let routes = routeDesk
        desk.stand(in: ProbeDialer())
        music.stand(in: ProbeMusic.silent())
        messages.stand(in: ProbeMessenger())
        routes.stand(in: ProbeRouteOpener())
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            await runFlowTest(name)
            desk.restore()
            music.restore()
            messages.restore()
            routes.restore()
            flowMark("FLOWTEST finished cmd=\(name)")
            testRunning = false
        }
    }
    #endif
}
