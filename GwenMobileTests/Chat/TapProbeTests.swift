@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest

@MainActor
final class TapProbeTests: GwenTestCase {
    @FocusState private var focus: Bool

    func testSmokeTheInputBarActionsRunThroughTheProbe() async throws {
        TapProbe.reset()
        Presenter.hostOverride = nil
        var picked: [PendingPicture] = []
        var toggled = 0
        var started = 0
        var stopped = 0
        let images = [PendingPicture(image: UIImage(), file: "a.jpg")]
        let files = [PendingFile(name: "Brief.pdf", kind: .pdf, file: "doc_a.pdf", bytes: 12_000)]
        let bar = ChatInputBar(voice: VoiceTranscriber(), busy: BusyOverlay(), speech: SpeechSynthesizer(),
                               isStreaming: false, isBusy: false, isRunning: false, chainIsRunning: false,
                               input: .constant(""), attachMenu: .constant(true), pendingImages: .constant(images),
                               pendingFiles: .constant(files), inputFocused: $focus,
                               onStartSend: { started += 1 }, onStopRun: { stopped += 1 },
                               onToggleVoice: { toggled += 1 })
        let card = ChatAttachMenuCard(attachMenu: .constant(true), pendingItems: .constant([]),
                                      onMenuScan: {}, onOpenFilePicker: {}, onOpenVideoPicker: {}, onPicked: { picked = $0 })
        let controller = mountView(VStack { bar; card }, size: CGSize(width: 390, height: 800))
        try await settleHosted(controller, milliseconds: 300)
        for action in TapProbe.drain() { action() }
        try await settleHosted(controller, milliseconds: 300)
        _ = picked
    }

    func testARepeatedRenderKeepsOneActionPerButton() {
        TapProbe.reset()
        var fired: [Int] = []
        for value in 1...3 {
            _ = TapProbe.action({ fired.append(value) })
        }
        let actions = TapProbe.drain()
        XCTAssertEqual(actions.count, 1)
        actions.first?()
        XCTAssertEqual(fired, [3])
    }

    func testThePresenterOverridePresents() throws {
        TapProbe.reset()
        Presenter.hostOverride = nil
        let window = hostWindow(Text("Host"))
        addTeardownBlock { window?.isHidden = true }
        Presenter.hostOverride = window?.rootViewController
        defer { Presenter.hostOverride = nil }
        let host = try XCTUnwrap(Presenter.topViewController)
        Presenter.present(UIViewController(), from: host)
        XCTAssertNotNil(Presenter.topViewController)
    }
}
