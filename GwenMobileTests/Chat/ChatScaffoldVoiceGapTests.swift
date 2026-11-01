@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit
@testable import GwenMobileProbes

@MainActor
private final class VoiceGapSource: FinalizingTranscribing {
    let label = "voice-gap"
    private(set) var isCapturing = false
    var spoken: [String] = []
    var emitted: String?
    private var delivered = 0
    private var textHandler: (@MainActor (String) -> Void)?

    func start(locale: Locale, hints: [String],
               onText: @escaping @MainActor (String) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) async throws {
        isCapturing = true
        textHandler = onText
        if delivered < spoken.count {
            let text = spoken[delivered]
            delivered += 1
            emitted = text
            onText(text)
        }
    }

    func stop() { isCapturing = false }

    func settle() async -> String? { emitted }

    func emit(_ text: String) {
        emitted = text
        textHandler?(text)
    }
}

@MainActor
final class ChatScaffoldVoiceGapTests: GwenTestCase {
    private let hosted = HostedChatView()

    override func setUp() {
        super.setUp()
        MockHTTP.install(MockHTTP.defaultHandler)
    }

    override func tearDown() async throws {
        MockHTTP.uninstall()
        ProbeHook.start = nil
        hosted.close()
        try await super.tearDown()
    }

    private func makeView(_ prefix: String, voice: VoiceTranscriber,
                          configure: (ChatStore) -> Void = { _ in })
        async throws -> (ChatView, ChatStore) {
        let store = HostedChatView.store(temporaryPaths(prefix))
        AppSettings.shared.setKey("gap-voice-key", for: AppSettings.shared.provider)
        configure(store)
        ChatView.defaultVoiceFactory = { voice }
        return (try await hosted.open(store, in: self), store)
    }

    private func hostedView(_ prefix: String, voice: VoiceTranscriber) async throws -> ChatView {
        let (_, store) = try await makeView(prefix, voice: voice)
        return try await hosted.host(ScenePhaseHost(chat: ChatView(listenToken: .constant(0))
                                                        .environmentObject(store)),
                                     in: self, settle: .milliseconds(800))
    }

    func testTheVoicePathsWithAFakeSource() async throws {
        let source = VoiceGapSource()
        source.spoken = ["Hallo Welt", "ruhe"]
        let voice = VoiceTranscriber(makeSource: { source }, microphoneAllowed: { true },
                                     sentCue: ChosenCue(chosen: { "" }, chime: ChimePlayer(tone: .sent)))
        let (view, _) = try await makeView("gap-voice-source", voice: voice)
        view.startRecording(from: "test")
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(view.voice.lastSessionListened || !view.input.isEmpty || view.voice.state != .idle)
        view.abortVoice()
        let listenOff = view.settings.voice.listenOffWord
        view.settings.voice.listenOffWord = "ruhe"
        view.settings.voice.listenMode = true
        view.followListenGate(view.listenGate)
        try await Task.sleep(for: .milliseconds(500))
        view.voiceDidTranscribe("ruhe")
        view.settings.voice.listenMode = false
        view.settings.voice.listenOffWord = listenOff
        view.abortVoice()
        try await view.microphone.setVoiceProcessing(false)
        dismissPresentedSheets()
    }

    func testListeningModeUsesEchoCancellation() async throws {
        let source = VoiceGapSource()
        let voice = VoiceTranscriber(makeSource: { source }, microphoneAllowed: { true },
                                     sentCue: ChosenCue(chosen: { "" }, chime: ChimePlayer(tone: .sent)))
        let (_, store) = try await makeView("gap-listen-echo", voice: voice)
        let view = try await hosted.host(ScenePhaseHost(chat: ChatView(listenToken: .constant(0))
                                                            .environmentObject(store)),
                                         in: self, settle: .milliseconds(800))
        view.settings.voice.listenMode = true
        view.followListenGate(view.listenGate)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(view.microphone.isVoiceProcessing)
        view.toggleListenMode()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(view.microphone.isVoiceProcessing)
        dismissPresentedSheets()
    }

    func testListeningModeStartsTheCancelListenerWhileTheAnswerRuns() async throws {
        let source = VoiceGapSource()
        let voice = VoiceTranscriber(makeSource: { source }, microphoneAllowed: { true },
                                     sentCue: ChosenCue(chosen: { "" }, chime: ChimePlayer(tone: .sent)))
        let view = try await hostedView("gap-listen-cancel-session", voice: voice)
        view.settings.voice.listenMode = true
        view.settings.voice.conversationMode = false
        view.isBusy = true
        view.followListenGate(view.listenGate)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(view.voice.isCancelSession)
        XCTAssertEqual(view.voice.state, .recording)
        view.isBusy = false
        view.followListenGate(view.listenGate)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertFalse(view.voice.isCancelSession)
        XCTAssertEqual(view.voice.state, .waiting)
        view.settings.voice.listenMode = false
        view.abortVoice()
        try? await view.microphone.setVoiceProcessing(false)
        dismissPresentedSheets()
    }

    func testTheListeningCancelWordStopsAndSpeaksFeedback() async throws {
        let source = VoiceGapSource()
        let voice = VoiceTranscriber(makeSource: { source }, microphoneAllowed: { true },
                                     sentCue: ChosenCue(chosen: { "" }, chime: ChimePlayer(tone: .sent)))
        let view = try await hostedView("gap-listen-cancel", voice: voice)
        view.settings.voice.listenMode = true
        view.settings.voice.conversationMode = false
        view.settings.voice.cancelWord = "abbrechen"
        view.isBusy = true
        view.followListenGate(view.listenGate)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(view.voice.isCancelSession)
        source.emit("abbrechen")
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(view.speechInterrupted)
        XCTAssertTrue(view.voiceCancelFeedback)
        XCTAssertTrue(view.speech.isSpeaking)
        view.isBusy = false
        view.settings.voice.listenMode = false
        view.speech.stop()
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertFalse(view.voiceCancelFeedback)
        dismissPresentedSheets()
    }

    func testConversationModeStartsAndStopsTheListeningSession() async throws {
        let source = VoiceGapSource()
        let voice = VoiceTranscriber(makeSource: { source }, microphoneAllowed: { true },
                                     sentCue: ChosenCue(chosen: { "" }, chime: ChimePlayer(tone: .sent)))
        let (_, store) = try await makeView("gap-conversation", voice: voice)
        let view = try await hosted.host(ScenePhaseHost(chat: ChatView(listenToken: .constant(0))
                                                            .environmentObject(store)),
                                         in: self, settle: .milliseconds(800))
        view.settings.voice.listenMode = false
        view.settings.voice.conversationMode = false
        view.settings.voice.dictationSilenceSeconds = 3
        view.voice.cancel()
        try await Task.sleep(for: .milliseconds(150))
        view.toggleConversationMode()
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(view.settings.voice.conversationMode)
        XCTAssertTrue(view.speaksWhileAnswering)
        XCTAssertFalse(view.settings.voice.listenMode)
        XCTAssertEqual(view.voice.state, .recording)
        XCTAssertEqual(view.voice.timing.silence, 3)
        view.toggleConversationMode()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(view.settings.voice.conversationMode)
        XCTAssertEqual(view.voice.state, .idle)
    }

    func testConversationHearingSendsTheNewTurn() async throws {
        let source = VoiceGapSource()
        let voice = VoiceTranscriber(makeSource: { source }, microphoneAllowed: { true },
                                     sentCue: ChosenCue(chosen: { "" }, chime: ChimePlayer(tone: .sent)))
        let (view, store) = try await makeView("gap-conversation-turn", voice: voice)
        view.settings.voice.conversationMode = true
        view.settings.voice.listenMode = false
        view.voice.cancel()
        try await Task.sleep(for: .milliseconds(150))
        view.voiceDidTranscribe("Was ist die Hauptstadt von Frankreich?")
        try await Task.sleep(for: .milliseconds(1200))
        let messages = store.current?.messages ?? []
        XCTAssertTrue(messages.contains { $0.role == .user && $0.text.contains("Hauptstadt") })
        view.settings.voice.conversationMode = false
    }

    func testSpeakingInterruptsTheRunningAnswerWithoutStoppingListening() async throws {
        let source = VoiceGapSource()
        let voice = VoiceTranscriber(makeSource: { source }, microphoneAllowed: { true },
                                     sentCue: ChosenCue(chosen: { "" }, chime: ChimePlayer(tone: .sent)))
        let (view, _) = try await makeView("gap-conversation-interrupt", voice: voice)
        view.settings.voice.conversationMode = true
        let running = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        view.runTask = running
        view.userStartedSpeaking()
        await view.settleInterruptedRun()
        XCTAssertNil(view.runTask)
        XCTAssertTrue(running.isCancelled)
        view.settings.voice.conversationMode = false
    }

    func testAnInterruptionThatNeverBecomesATurnFreesTheSendButton() async throws {
        let source = VoiceGapSource()
        let voice = VoiceTranscriber(makeSource: { source }, microphoneAllowed: { true },
                                     sentCue: ChosenCue(chosen: { "" }, chime: ChimePlayer(tone: .sent)))
        let (view, _) = try await makeView("gap-conversation-unanswered", voice: voice)
        view.settings.voice.conversationMode = true
        MockHTTPProtocol.dataDelay = 1
        defer { MockHTTPProtocol.dataDelay = 0 }
        view.input = "Wie spät ist es in Tokio?"
        view.startSend()
        let running = try XCTUnwrap(view.runTask)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertNotNil(view.runTask)
        XCTAssertTrue(view.isBusy)
        view.userStartedSpeaking()
        await running.value
        XCTAssertTrue(running.isCancelled)
        XCTAssertNil(view.runTask)
        view.settings.voice.conversationMode = false
    }

    func testTheConversationCancelWordStopsAndSpeaksFeedback() async throws {
        let source = VoiceGapSource()
        let voice = VoiceTranscriber(makeSource: { source }, microphoneAllowed: { true },
                                     sentCue: ChosenCue(chosen: { "" }, chime: ChimePlayer(tone: .sent)))
        let (view, _) = try await makeView("gap-conversation-stop", voice: voice)
        view.settings.voice.conversationMode = true
        let running = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        view.runTask = running
        view.handleVoiceCancel()
        XCTAssertTrue(view.speechInterrupted)
        XCTAssertTrue(view.voiceCancelFeedback)
        XCTAssertTrue(view.speech.isSpeaking)
        view.settings.voice.conversationMode = false
        view.speech.stop()
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertFalse(view.voiceCancelFeedback)
        XCTAssertNil(view.runTask)
    }

    func testAnInterruptedAnswerDoesNotSpeak() async throws {
        let source = VoiceGapSource()
        let voice = VoiceTranscriber(makeSource: { source }, microphoneAllowed: { true },
                                     sentCue: ChosenCue(chosen: { "" }, chime: ChimePlayer(tone: .sent)))
        let (view, _) = try await makeView("gap-interrupted-speech", voice: voice)
        view.settings.voice.speakAnswers = true
        view.speechInterrupted = true
        view.announceAnswer("Diese Antwort darf nicht mehr gesprochen werden.")
        XCTAssertFalse(view.speech.isSpeaking)
        view.speechInterrupted = false
    }

    func testSmokeTheScaffoldCameraListingAndProbePaths() async throws {
        let settings = AppSettings.shared
        let provider = settings.provider
        let savedProfile = settings.profile
        settings.updateProfile(of: provider) { profile in
            profile.listingVersion = 0
        }
        MockHTTP.install { _ in (200, Data(#"{"data":[{"id":"gap-model"}]}"#.utf8)) }
        ProbeHook.start = { _ in }
        let source = VoiceGapSource()
        let voice = VoiceTranscriber(makeSource: { source }, microphoneAllowed: { true },
                                     sentCue: ChosenCue(chosen: { "" }, chime: ChimePlayer(tone: .sent)))
        let (view, _) = try await makeView("gap-scaffold-probe", voice: voice)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { _ in }
        CameraPresenter.shared.onImage?(image)
        try await Task.sleep(for: .milliseconds(600))
        view.syncPendingAlerts()
        settings.profiles[provider] = savedProfile
        dismissPresentedSheets()
    }

    func testSmokeTheScenePhaseActivationRuns() async throws {
        let source = VoiceGapSource()
        let voice = VoiceTranscriber(makeSource: { source }, microphoneAllowed: { true },
                                     sentCue: ChosenCue(chosen: { "" }, chime: ChimePlayer(tone: .sent)))
        let (view, _) = try await makeView("gap-scene-phase", voice: voice)
        let host = ScenePhaseHost(chat: ChatView(listenToken: .constant(0)).environmentObject(view.store))
        _ = try await hosted.host(host, in: self, settle: .milliseconds(800))
        dismissPresentedSheets()
    }
}

@MainActor
private struct ScenePhaseHost: View {
    let chat: AnyView
    @State private var phase: ScenePhase = .background

    init(chat: some View) {
        self.chat = AnyView(chat)
    }

    var body: some View {
        chat
            .environment(\.scenePhase, phase)
            .onAppear {
                Task {
                    try? await Task.sleep(for: .milliseconds(200))
                    phase = .active
                }
            }
    }
}
