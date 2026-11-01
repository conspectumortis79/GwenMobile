@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import XCTest

@MainActor
final class ListenPresenceTests: GwenTestCase {
    func testTheGlowNeedsTheForegroundNoSheetAndAWakeWord() {
        XCTAssertEqual(glow(foreground: false), .hidden)
        XCTAssertEqual(glow(sheetOpen: true), .hidden)
        XCTAssertEqual(glow(wakeWord: false), .hidden)
    }

    func testTheGlowShowsOnlyForTheWakeWordRecording() {
        XCTAssertEqual(glow(wakeWord: true, voice: .recording), .listening)
        XCTAssertEqual(glow(wakeWord: false, voice: .recording), .hidden)
    }

    func testTheGlowGoesOutWhenTheRequestIsSent() {
        XCTAssertEqual(glow(wakeWord: true, voice: .idle), .hidden)
        XCTAssertEqual(glow(wakeWord: true, voice: .processing), .hidden)
    }

    func testTheGlowHidesWhenTheWakeWordTurnIsDone() {
        XCTAssertEqual(glow(wakeWord: true, voice: .idle), .hidden)
        XCTAssertEqual(glow(wakeWord: true, voice: .waiting), .hidden)
    }

    func testTheWakeGreetingIsOneOfTheLocalizedPhrases() {
        let phrases = Set(WakeGreeting.keys.map { L.t($0) })
        XCTAssertEqual(phrases.count, WakeGreeting.keys.count)
        for _ in 0..<20 {
            XCTAssertTrue(phrases.contains(WakeGreeting.random()))
        }
    }

    func testTheLiveActivityStaysHiddenWhileTheAppIsActive() {
        XCTAssertEqual(plan(foreground: true), .hidden)
        XCTAssertEqual(plan(sheetOpen: true), .hidden)
        XCTAssertEqual(plan(listenMode: false, conversationMode: false), .hidden)
        XCTAssertEqual(plan(microphoneLive: false), .hidden)
    }

    func testTheLiveActivityAppearsArmedInTheBackground() {
        XCTAssertEqual(plan(foreground: false),
                       .visible(mode: .listen, phase: .armed, titleKey: "listen_live_armed"))
    }

    func testTheLiveActivityTracksRecordingAndProcessing() {
        XCTAssertEqual(plan(foreground: false, voice: .recording),
                       .visible(mode: .listen, phase: .recording, titleKey: "listen_live_armed"))
        XCTAssertEqual(plan(foreground: false, voice: .processing),
                       .visible(mode: .listen, phase: .processing, titleKey: "listen_live_processing"))
        XCTAssertEqual(plan(foreground: false, working: true),
                       .visible(mode: .listen, phase: .processing, titleKey: "listen_live_processing"))
    }

    func testTheLiveActivityUsesConversationMode() {
        XCTAssertEqual(plan(foreground: false, listenMode: false, conversationMode: true),
                       .visible(mode: .conversation, phase: .armed, titleKey: "listen_live_armed"))
    }

    private func glow(foreground: Bool = true, sheetOpen: Bool = false, wakeWord: Bool = true,
                      voice: VoiceTranscriber.State = .idle) -> ListenGlowPhase {
        ListenGlowPolicy.phase(foreground: foreground, sheetOpen: sheetOpen, wakeWord: wakeWord,
                               voice: voice)
    }

    private func plan(foreground: Bool = false, sheetOpen: Bool = false, listenMode: Bool = true,
                      conversationMode: Bool = false, microphoneLive: Bool = true,
                      voice: VoiceTranscriber.State = .idle, working: Bool = false) -> ListenLivePlan {
        ListenLivePlan.plan(foreground: foreground, sheetOpen: sheetOpen, listenMode: listenMode,
                            conversationMode: conversationMode, microphoneLive: microphoneLive,
                            voice: voice, working: working)
    }
}
