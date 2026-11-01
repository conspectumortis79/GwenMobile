@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit

@MainActor
final class ChatInputBarGap2Tests: GwenTestCase {
    @FocusState private var focus: Bool

    private func bar(voice: VoiceTranscriber, speech: SpeechSynthesizer = SpeechSynthesizer(),
                     streaming: Bool = false, busy: Bool = false, running: Bool = false,
                     input: Binding<String> = .constant(""),
                     onStartSend: @escaping () -> Void = {}, onStopRun: @escaping () -> Void = {})
        -> ChatInputBar {
        ChatInputBar(voice: voice, busy: BusyOverlay(), speech: speech,
                     isStreaming: streaming, isBusy: busy, isRunning: running, chainIsRunning: false,
                     input: input, attachMenu: .constant(false), pendingImages: .constant([]), pendingFiles: .constant([]), inputFocused: $focus,
                     onStartSend: onStartSend, onStopRun: onStopRun, onToggleVoice: {})
    }

    func testSmokeTheVoiceAndStopStatesDrain() async throws {
        let voice = VoiceTranscriber()
        voice.state = .recording
        voice.remaining = 5
        let first = mountView(bar(voice: voice), size: CGSize(width: 390, height: 260))
        try await settleHosted(first, milliseconds: 200)
        runProbedActions()
        let speech = SpeechSynthesizer()
        speech.isSpeaking = true
        let second = mountView(bar(voice: VoiceTranscriber(), speech: speech),
                               size: CGSize(width: 390, height: 220))
        try await settleHosted(second, milliseconds: 200)
        runProbedActions()
        let third = mountView(bar(voice: VoiceTranscriber(), streaming: true),
                              size: CGSize(width: 390, height: 220))
        try await settleHosted(third, milliseconds: 200)
        runProbedActions()
        voice.state = .waiting
        let fourth = mountView(bar(voice: voice), size: CGSize(width: 390, height: 220))
        try await settleHosted(fourth, milliseconds: 200)
        runProbedActions()
    }

    func testTheFieldAndPickerChangesRun() async throws {
        let counter = InputBarCounter()
        let host = mountView(InputBarObservedHost(voice: VoiceTranscriber(), counter: counter),
                             size: CGSize(width: 390, height: 240))
        try await settleHosted(host, milliseconds: 700)
        runProbedActions()
        XCTAssertGreaterThan(counter.started, 0)
    }
}

@MainActor
private final class InputBarCounter: ObservableObject {
    @Published var started = 0
}

@MainActor
private struct InputBarObservedHost: View {
    let voice: VoiceTranscriber
    @ObservedObject var counter: InputBarCounter
    @State private var input = ""
    @FocusState private var focus: Bool

    var body: some View {
        ChatInputBar(voice: voice, busy: BusyOverlay(), speech: SpeechSynthesizer(),
                     isStreaming: false, isBusy: false, isRunning: false, chainIsRunning: false,
                     input: $input, attachMenu: .constant(false), pendingImages: .constant([]), pendingFiles: .constant([]), inputFocused: $focus,
                     onStartSend: { counter.started += 1 },
                     onStopRun: {}, onToggleVoice: {})
            .onAppear {
                Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    input = "Hallo\n"
                }
            }
    }
}
