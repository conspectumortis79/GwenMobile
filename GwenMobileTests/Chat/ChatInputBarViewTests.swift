@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit

@MainActor
final class ChatInputBarViewTests: GwenTestCase {
    @FocusState private var focus: Bool

    private func bar(input: String = "", streaming: Bool = false, busy: Bool = false,
                     running: Bool = false, chain: Bool = false,
                     voice: VoiceTranscriber = VoiceTranscriber(), conversation: Bool = false,
                     attachMenu: Bool = false,
                     images: [PendingPicture] = [], files: [PendingFile] = []) -> ChatInputBar {
        ChatInputBar(voice: voice, busy: BusyOverlay(), speech: SpeechSynthesizer(),
                     isStreaming: streaming, isBusy: busy, isRunning: running, chainIsRunning: chain,
                     conversationMode: conversation,
                     input: .constant(input), attachMenu: .constant(attachMenu), pendingImages: .constant(images),
                     pendingFiles: .constant(files), inputFocused: $focus,
                     onStartSend: {}, onStopRun: {}, onToggleVoice: {})
    }

    func testTheIdleBarDrawsEmpty() async throws {
        let controller = mountView(bar(), size: CGSize(width: 390, height: 220))
        try await settleHosted(controller)
        XCTAssertNotNil(renderView(bar(), width: 390))
    }

    func testTheStopStatesDraw() async throws {
        for (streaming, busy, running, chain) in [(true, false, false, false),
                                                  (false, true, false, false),
                                                  (false, false, true, false),
                                                  (false, false, false, true)] {
            let controller = mountView(bar(streaming: streaming, busy: busy, running: running, chain: chain),
                                       size: CGSize(width: 390, height: 220))
            try await settleHosted(controller, milliseconds: 150)
            XCTAssertNotNil(controller.view.window)
        }
    }

    func testTheConversationModeDrawsItsHint() async throws {
        let voice = VoiceTranscriber()
        voice.state = .recording
        let bar = self.bar(voice: voice, conversation: true)
        let controller = mountView(bar, size: CGSize(width: 390, height: 220))
        try await settleHosted(controller, milliseconds: 150)
        XCTAssertNotNil(controller.view.window)
        XCTAssertNotNil(renderView(bar, width: 390))
    }

    func testConversationListeningDoesNotTurnTheSendButtonIntoStop() {
        let voice = VoiceTranscriber()
        voice.state = .recording
        let conversation = self.bar(input: "Hallo", voice: voice, conversation: true)
        XCTAssertFalse(conversation.isStoppable)
        let dictation = self.bar(input: "Hallo", voice: voice)
        XCTAssertTrue(dictation.isStoppable)
    }

    func testTheBarDrawsWithTextAndAttachments() async throws {
        let images = [PendingPicture(image: UIImage(), file: "a.jpg")]
        let files = [PendingFile(name: "Brief.pdf", kind: .pdf, file: "doc_a.pdf", bytes: 12_000)]
        let controller = mountView(bar(input: "Frage", images: images, files: files),
                                   size: CGSize(width: 390, height: 260))
        try await settleHosted(controller, milliseconds: 200)
        XCTAssertGreaterThan(controller.sizeThatFits(in: CGSize(width: 390, height: 800)).height, 40)
        XCTAssertNotNil(renderView(bar(input: "Frage", images: images, files: files), width: 390))
    }

    func testTheVoiceStatesDraw() async throws {
        for state in [VoiceTranscriber.State.waiting, .recording, .processing, .idle] {
            let voice = VoiceTranscriber()
            voice.state = state
            let bar = self.bar(voice: voice)
            let controller = mountView(bar, size: CGSize(width: 390, height: 220))
            try await settleHosted(controller, milliseconds: 150)
            XCTAssertNotNil(controller.view.window)
        }
    }

    func testTheBarDrawsWithAnOpenAttachMenu() async throws {
        let images = [PendingPicture(image: UIImage(), file: "a.jpg")]
        let files = [PendingFile(name: "Brief.pdf", kind: .pdf, file: "doc_a.pdf", bytes: 12_000)]
        let bar = self.bar(input: "Frage", attachMenu: true, images: images, files: files)
        let controller = mountView(bar, size: CGSize(width: 390, height: 320))
        try await settleHosted(controller, milliseconds: 250)
        XCTAssertNotNil(controller.view.window)
    }

    func testTheBarShowsTheRecordingCountdown() async throws {
        let voice = VoiceTranscriber()
        voice.state = .recording
        voice.remaining = 3
        let bar = self.bar(voice: voice)
        let controller = mountView(bar, size: CGSize(width: 390, height: 220))
        try await settleHosted(controller, milliseconds: 150)
        XCTAssertNotNil(controller.view.window)
    }

    func testTheAttachMenuCardDraws() async throws {
        let card = ChatAttachMenuCard(attachMenu: .constant(true), pendingItems: .constant([]),
                                      onMenuScan: {}, onOpenFilePicker: {}, onOpenVideoPicker: {}, onPicked: { _ in })
        let controller = mountView(card, size: CGSize(width: 390, height: 300))
        try await settleHosted(controller, milliseconds: 250)
        XCTAssertNotNil(controller.view.window)
    }
}
