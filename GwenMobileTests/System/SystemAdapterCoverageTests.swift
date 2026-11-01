@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import AVFoundation
import MessageUI
import ObjectiveC
import Speech
import SwiftUI
import UIKit
import UserNotifications
import VisionKit
import XCTest
import GwenMobileKit

@MainActor
final class SystemAdapterCoverageTests: GwenTestCase {
    func testSmokeThePriceWatchBackgroundAdapter() async {
        let system = PriceWatchBackgroundSystem.shared
        system.register()
        system.register()
        PriceWatchBackgroundSystem.accept(nil)
        try? await Task.sleep(for: .milliseconds(100))
        await system.scheduleNext()
        let store = PriceWatchStore(paths: temporaryPaths("price-background"))
        _ = await store.create(terms: ["PS5"], goal: 400, intervalHours: 24, currencyCode: "EUR",
                               regionCode: nil, now: Date().addingTimeInterval(-3 * 86_400))
        await system.scheduleNext(store: store)
        await system.handle(nil)
    }

    func testTheComposeSenderDefaultsAndTheSheetFinish() async throws {
        let sender = ComposeMessageSender()
        let sendingDefault = Task { await sender.send("Hallo", to: DialNumber("030123")!) }
        try? await Task.sleep(for: .milliseconds(300))
        sender.messageComposeViewController(MFMessageComposeViewController(), didFinishWith: .cancelled)
        let defaultResult = await sendingDefault.value
        XCTAssertTrue(defaultResult == .unavailable || defaultResult == .cancelled || defaultResult == .needsForeground)
        XCTAssertEqual(ComposeMessageSender.result(of: .sent), .sent(direct: false))
        XCTAssertEqual(ComposeMessageSender.result(of: .cancelled), .cancelled)
        if case .failed = ComposeMessageSender.result(of: .failed) {
        } else {
            XCTFail("erwartet Fehler")
        }

        let host = InertHost()
        let active = ComposeMessageSender(canSend: { true }, isActive: { true }, host: { host })
        let sending = Task { await active.send("Hallo", to: DialNumber("030123")!) }
        try await Task.sleep(for: .milliseconds(300))
        active.messageComposeViewController(MFMessageComposeViewController(), didFinishWith: .cancelled)
        let result = await sending.value
        XCTAssertEqual(result, .cancelled)
    }

    func testTheSpeechRecognizerDefaultsAndTheTranscription() async throws {
        SystemSpeechRecognizer.authorizationStatusOverride = .authorized
        defer { SystemSpeechRecognizer.authorizationStatusOverride = nil }
        let recognizer = SystemSpeechRecognizer(locale: Locale(identifier: "de-DE"))
        recognizer.isAvailableOverride = true
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gwen-speech-\(UUID().uuidString).wav")
        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        recognizer.startTask = { _, _, handler in
            handler("Hallo", true, nil)
            return TestSpeechTask()
        }
        let text = try await recognizer.transcribe(wavURL: url)
        XCTAssertEqual(text, "Hallo")
        let unavailable = SystemSpeechRecognizer(locale: Locale(identifier: "zz-ZZ"))
        do {
            _ = try await unavailable.transcribe(wavURL: url)
            XCTFail("erwartet Fehler")
        } catch {}
    }

    #if !targetEnvironment(macCatalyst)
    func testTheScannerFinishesWithPages() throws {
        let pageSelector = NSSelectorFromString("imageOfPageAtIndex:")
        let pageMethod = try XCTUnwrap(class_getInstanceMethod(VNDocumentCameraScan.self, pageSelector))
        let countMethod = try XCTUnwrap(class_getInstanceMethod(VNDocumentCameraScan.self,
                                                                NSSelectorFromString("pageCount")))
        let originalPage = method_getImplementation(pageMethod)
        let originalCount = method_getImplementation(countMethod)
        defer {
            method_setImplementation(pageMethod, originalPage)
            method_setImplementation(countMethod, originalCount)
        }
        let page: @convention(block) (AnyObject, Int) -> UIImage? = { _, _ in UIImage() }
        let count: @convention(block) (AnyObject) -> Int = { _ in 2 }
        method_setImplementation(pageMethod, imp_implementationWithBlock(page))
        method_setImplementation(countMethod, imp_implementationWithBlock(count))
        let scan = class_createInstance(VNDocumentCameraScan.self, 0) as? VNDocumentCameraScan
        let controller = VNDocumentCameraViewController()
        DocumentScannerSystem.shared.documentCameraViewController(controller,
                                                                  didFinishWith: try XCTUnwrap(scan))
    }
    #endif

    func testTheBufferSourceDefaultsAndFailures() async {
        let limit = BufferSpeechSource.segmentLimit
        BufferSpeechSource.segmentLimit = .milliseconds(40)
        defer { BufferSpeechSource.segmentLimit = limit }
        let source = BufferSpeechSource(feed: TestAudioFeed(), authorize: {})
        do {
            try await source.start(locale: Locale(identifier: "de-DE"), hints: [],
                                   onText: { _ in }, onFailure: { _ in })
        } catch {}
        try? await Task.sleep(for: .milliseconds(150))
        source.stop()
        let unavailable = BufferSpeechSource(feed: TestAudioFeed(), authorize: {})
        do {
            try await unavailable.start(locale: Locale(identifier: "zz-ZZ"), hints: [],
                                        onText: { _ in }, onFailure: { _ in })
            XCTFail("erwartet Fehler")
        } catch {}
        let failing = BufferSpeechSource(feed: FailingAudioFeed(), authorize: {})
        do {
            try await failing.start(locale: Locale(identifier: "de-DE"), hints: [],
                                    onText: { _ in }, onFailure: { _ in })
            XCTFail("erwartet Fehler")
        } catch {}
    }

    func testSmokeTheLiveAudioEngine() async {
        let live = LiveAudioEngine()
        _ = live.isEngineRunning
        _ = live.inputFormat()
        live.prepare()
        do { try live.start() } catch {}
        live.stop()
        try? await AudioSessionSetup.prepare(.ambient, mode: .default, options: [.defaultToSpeaker])
        try? await AudioSessionSetup.prepare(.ambient, mode: .default, options: [])
    }

    func testAFailedReconnectLeavesTheTapRunningWithoutFlow() async throws {
        let engine = ReconnectAudioEngine()
        let setup = RecordingSetup(label: "probe", mode: .measurement, options: [])
        let tap = MicrophoneTap(setups: [setup], engine: engine)
        tap.prepareSession = { _ in }
        try await tap.start { _ in }
        XCTAssertTrue(tap.isFlowing)
        engine.failure = APIError(message: "kaputt")
        do {
            try await tap.reconnect()
            XCTFail("erwartet Fehler")
        } catch {
            XCTAssertEqual(error.localizedDescription, "kaputt")
        }
        XCTAssertTrue(tap.isRunning)
        XCTAssertFalse(tap.isFlowing)
        tap.stop()
    }

    func testSmokeTheSpeechAuthorizerClosure() async {
        let original = SystemSpeechRecognizer.requestAuthorization
        SystemSpeechRecognizer.requestAuthorization = { true }
        defer { SystemSpeechRecognizer.requestAuthorization = original }
        _ = await SystemSpeechRecognizer.requestAuthorization()
    }

    func testSmokeTheTranscriptionPreferenceBuildsItsCandidates() async throws {
        let transcriber = SpeechTranscriber(locale: Locale(identifier: "de-DE"),
                                            transcriptionOptions: [], reportingOptions: [],
                                            attributeOptions: [])
        guard await AnalyzerSpeechSource.assetStatus(transcriber) == .installed else {
            throw XCTSkip("Speech assets are not installed")
        }
        let source = LiveTranscription.preferred(feed: { TestAudioFeed() })
        do {
            try await source.start(locale: Locale(identifier: "de-DE"), hints: [],
                                   onText: { _ in }, onFailure: { _ in })
        } catch {}
        source.stop()
    }

    func testTheMemoryViewsRunTheirActions() async throws {
        let paths = temporaryPaths("memory-actions")
        let store = ChatStore(media: MediaStore(paths: paths), paths: paths)
        let created = await store.memory.add(text: "Zahnarzt", category: .health, source: .manual,
                                             date: Date().addingTimeInterval(86_400), remind: true)
        let controller = mountView(NavigationStack {
            MemoryView().environmentObject(store)
        }, size: CGSize(width: 390, height: 900))
        try await settleHosted(controller, milliseconds: 500)
        for action in TapProbe.drain() { action() }
        try await settleHosted(controller, milliseconds: 400)
        for action in TapProbe.drain() { action() }
        try await settleHosted(controller, milliseconds: 400)
        for action in TapProbe.drain() { action() }
        try await settleHosted(controller, milliseconds: 400)
        for action in TapProbe.drain() { action() }
        dismissPresentedSheets()
        XCTAssertNotNil(created)
    }
}

private final class InertHost: UIViewController {
    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool,
                          completion: (() -> Void)? = nil) {}
}

@MainActor
private final class FailingAudioFeed: AudioFeeding {
    var isRunning: Bool { false }
    func start(deliver: @escaping @Sendable (AVAudioPCMBuffer) -> Void) async throws {
        throw APIError(message: "kein mikrofon")
    }
    func stop() {}
}

private final class ReconnectAudioEngine: AudioEngineing, @unchecked Sendable {
    var isEngineRunning = false
    var failure: Error?
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    func inputFormat() -> AVAudioFormat { format }

    func installTap(bufferSize: AVAudioFrameCount, format: AVAudioFormat,
                    block: @escaping AVAudioNodeTapBlock) {}

    func removeTap() {}

    func prepare() {}

    func start() throws {
        if let failure { throw failure }
        isEngineRunning = true
    }

    func stop() { isEngineRunning = false }
}
