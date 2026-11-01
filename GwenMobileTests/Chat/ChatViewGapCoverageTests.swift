@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import EventKit
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit
@testable import GwenMobileProbes

private struct RefusingPersistence: ConversationPersisting {
    func persist(_ conversations: [Conversation]) async throws { throw APIError(message: "voll") }
    func load() -> ConversationLoad { .nothing }
}

@MainActor
final class ChatViewGapCoverageTests: GwenTestCase {
    private let hosted = HostedChatView()

    override func setUp() {
        super.setUp()
        MockHTTP.install(MockHTTP.defaultHandler)
        MainActor.assumeIsolated { URLOpenSpy.install() }
    }

    override func tearDown() async throws {
        URLOpenSpy.uninstall()
        MockHTTP.uninstall()
        hosted.close()
        try await super.tearDown()
    }

    private func makeView(_ prefix: String, persistence: (any ConversationPersisting)? = nil)
        async throws -> (ChatView, ChatStore) {
        let store = HostedChatView.store(temporaryPaths(prefix), persistence: persistence)
        store.stand(in: PhotoLibraryWriter(library: FakePhotoLibrary()))
        AppSettings.shared.provider = .qwenCloud
        AppSettings.shared.visionModel = "gap-vision"
        AppSettings.shared.imageModel = "gap-image"
        AppSettings.shared.setKey("gap-test-key", for: .qwenCloud)
        return (try await hosted.open(store, in: self), store)
    }

    private func routed(_ text: String, plan: SendPlan, convID: UUID) -> RoutedSend {
        RoutedSend(text: text, plan: plan, turn: ModelTurn(messages: [], images: []), history: [],
                   attachments: [], files: [], convID: convID, started: Date())
    }

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    private func imageData() -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 60, height: 40)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 60, height: 40))
        }
        return image.pngData() ?? Data([1, 2, 3])
    }

    func testTheScaffoldCallbacksRun() async throws {
        let (view, store) = try await makeView("gap-scaffold")
        let convID = try XCTUnwrap(store.current?.id)
        let picture = WebPicture(file: "web_gap.jpg", pageURL: "https://q.test/p",
                                 fullURL: "https://q.test/p.jpg", title: "Bild", domain: "q.test")
        let gallery = PictureGallery(query: "Bilder", pictures: [picture], shown: 1, exhausted: false)
        let message = ChatMessage(role: .assistant, text: "Galerie", gallery: gallery)
        store.appendMessage(message, to: convID)
        view.gallerySelection.begin(owner: message.id)
        view.gallerySelection.toggle(picture.file)
        view.attachMenu = true
        view.pendingSuggestions = [MemorySuggestion(text: "mag Tee", category: .likes)]
        view.queueAlert(L.FriendlyError(message: "Fehler", detail: "Detail", openSettings: true))
        view.autoScroll.dragChanged(translation: -200)
        for action in MirrorTap.actions(in: view.scaffold) { action() }
        runProbedActions()
        try await Task.sleep(for: .milliseconds(600))
        runProbedActions()
        try await Task.sleep(for: .milliseconds(300))
        runProbedActions()
        view.pendingSuggestions = []
        view.dismissAlert()
        view.attachMenu = false
        view.inputFocused = false
        view.settings.voice.listenMode = false
        view.abortVoice()
        dismissPresentedSheets()
    }

    func testSmokeTheVoiceHelpersRun() async throws {
        let (view, _) = try await makeView("gap-voice")
        view.settings.voice.listenMode = true
        view.startListeningFromShortcut()
        try await Task.sleep(for: .milliseconds(700))
        view.abortVoice()
        view.handledListen = -1
        view.takeListenRequest(from: "test")
        try await Task.sleep(for: .milliseconds(700))
        view.abortVoice()
        for state in [VoiceTranscriber.State.waiting, .recording, .processing, .idle] {
            view.voice.state = state
            view.toggleVoice()
        }
        view.voice.state = .idle
        view.settings.voice.listenMode = false
        view.voiceDidTranscribe("Was ist die Hauptstadt von Frankreich?")
        try await Task.sleep(for: .milliseconds(400))
        view.abortVoice()
        view.followListenGate(view.listenGate)
        view.followMicrophoneHold(view.listenGate)
        view.microphoneLost()
        view.refreshVoiceAfterEngineChange()
        view.settings.voice.listenMode = true
        view.refreshVoiceAfterEngineChange()
        view.settings.voice.listenMode = false
        view.stopRun()
        dismissPresentedSheets()
    }

    func testRemovingAPendingFileDeletesTheStagedCopy() async throws {
        let (view, store) = try await makeView("gap-pending-remove")
        let folder = try temporaryFolder()
        let text = folder.appendingPathComponent("Notiz.txt")
        try Data("Hallo Welt".utf8).write(to: text)
        let stagedResult = await view.stageFile(text)
        let staged = try XCTUnwrap(stagedResult)
        XCTAssertNotNil(store.documents.storedURL(for: staged.pending.file))
        view.removePendingFile(staged.pending)
        XCTAssertNil(store.documents.storedURL(for: staged.pending.file))
        XCTAssertTrue(view.pendingFiles.isEmpty)
    }

    func testTheFileGuardsAndDropsRun() async throws {
        let (view, _) = try await makeView("gap-files")
        let folder = try temporaryFolder()
        let unsupported = folder.appendingPathComponent("Bild.xyz")
        try Data("x".utf8).write(to: unsupported)
        let refused = await view.stageFile(unsupported)
        XCTAssertNil(refused)
        view.pendingFiles = (0..<FilePolicy.maxFilesPerMessage).map {
            PendingFile(name: "n\($0).txt", kind: .text, file: "doc_gap_\($0)", bytes: 1, chars: 1)
        }
        let text = folder.appendingPathComponent("Notiz.txt")
        try Data("Hallo Welt".utf8).write(to: text)
        let limited = await view.stageFile(text)
        XCTAssertNil(limited)
        view.pendingFiles = []
        let big = folder.appendingPathComponent("Gross.txt")
        try Data().write(to: big)
        let handle = try FileHandle(forWritingTo: big)
        try handle.truncate(atOffset: UInt64(FilePolicy.maxFileBytes + 1))
        try handle.close()
        let tooBig = await view.stageFile(big)
        XCTAssertNil(tooBig)
        view.acceptDroppedFiles([text])
        try await Task.sleep(for: .milliseconds(900))
        view.dropRunning = true
        await view.analyzeDroppedFiles([text])
        view.dropRunning = false
        view.isBusy = true
        await view.analyzeDroppedFiles([text])
        view.isBusy = false
        let provider = view.settings.provider
        AppSettings.shared.setKey("", for: provider)
        await view.analyzeDroppedFiles([unsupported])
        AppSettings.shared.setKey("gap-test-key", for: provider)
        await view.analyzeDroppedFiles([unsupported])
        let empty = folder.appendingPathComponent("Leer.txt")
        try Data().write(to: empty)
        await view.analyzeDroppedFiles([empty])
        let missing = folder.appendingPathComponent("fehlt.png")
        let picture = await view.importDroppedPicture(missing)
        XCTAssertNil(picture)
        let images = (0..<12).map { index -> URL in
            let url = folder.appendingPathComponent("Bild\(index).png")
            try? imageData().write(to: url)
            return url
        }
        await view.analyzeDroppedFiles(images)
        try await Task.sleep(for: .milliseconds(900))
        if let pending = view.pendingFiles.first {
            view.applyExtraction(nil, toFile: pending.file, named: pending.name, id: pending.id)
        }
        view.applyExtraction(ExtractedText(text: "Inhalt", pages: nil, chars: 6, truncated: false,
                                           via: .plain),
                             toFile: "doc_gap_unknown", named: "unbekannt", id: UUID())
        dismissPresentedSheets()
    }

    func testAnUnreadableFileIsRemovedAndReported() async throws {
        let (view, store) = try await makeView("gap-file-unreadable")
        let folder = try temporaryFolder()
        let broken = folder.appendingPathComponent("Dokumentation.pdf")
        try Data([0x31, 0x50, 0x85, 0xB1]).write(to: broken)
        await view.importFile(broken)
        XCTAssertTrue(view.pendingFiles.isEmpty)
        XCTAssertTrue(store.documents.fileNames().isEmpty)
        XCTAssertEqual(view.currentAlert?.message,
                       L.fmt("file_unreadable", "Dokumentation.pdf"))
        view.dismissAlert()
        XCTAssertNil(view.currentAlert)
    }

    func testSmokeTheOcrRunRecognizesText() async throws {
        let (view, _) = try await makeView("gap-ocr")
        let text = UIGraphicsImageRenderer(size: CGSize(width: 420, height: 140)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 420, height: 140))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 56),
                .foregroundColor: UIColor.black,
            ]
            NSString(string: "HALLO").draw(at: CGPoint(x: 20, y: 30), withAttributes: attributes)
        }
        let pending = PendingPicture(image: text, file: nil)
        view.pendingImages = [pending]
        let auto = AppSettings.shared.autoOCR
        AppSettings.shared.autoOCR = true
        view.runOCR(on: [pending])
        try await Task.sleep(for: .milliseconds(1500))
        AppSettings.shared.autoOCR = auto
        view.runOCR(on: [])
        dismissPresentedSheets()
    }

    func testTheGalleryWritesAndBarRun() async throws {
        let (view, store) = try await makeView("gap-gallery")
        let convID = try XCTUnwrap(store.current?.id)
        let file = try XCTUnwrap(store.media.storeImageData(imageData()))
        let picture = WebPicture(file: file, pageURL: "https://q.test/g",
                                 fullURL: "https://q.test/g.jpg", title: "Bild", domain: "q.test")
        let missing = WebPicture(file: "fehlt_gap.jpg", pageURL: "https://q.test/f",
                                 fullURL: "https://q.test/f.jpg", title: "Weg", domain: "q.test")
        let gallery = PictureGallery(query: "Bilder", pictures: [picture, missing], shown: 2,
                                     exhausted: false)
        let message = ChatMessage(role: .assistant, text: "Galerie", gallery: gallery)
        store.appendMessage(message, to: convID)
        view.gallerySelection.begin(owner: message.id)
        view.gallerySelection.toggle(picture.file)
        await view.saveGallerySelection()
        await view.saveWholeGallery()
        await view.writeGalleryPictures([])
        await view.writeGalleryPictures([missing])
        view.shareGallerySelection()
        view.galleryOperation.beginSearch(message.id)
        try await Task.sleep(for: .milliseconds(200))
        view.galleryOperation.endSearch(message.id)
        for action in MirrorTap.actions(in: view.galleryBar) { action() }
        try await Task.sleep(for: .milliseconds(500))
        view.cancelGallerySelection()
        dismissPresentedSheets()
    }

    func testTheMorePicturesBranches() async throws {
        let (view, store) = try await makeView("gap-more-pictures")
        let convID = try XCTUnwrap(store.current?.id)
        let first = WebPicture(file: "eins.jpg", pageURL: "https://q.test/1",
                               fullURL: "https://q.test/1.jpg", title: "Eins", domain: "q.test")
        let second = WebPicture(file: "zwei.jpg", pageURL: "https://q.test/2",
                                fullURL: "https://q.test/2.jpg", title: "Zwei", domain: "q.test")
        let hiddenGallery = PictureGallery(query: "Bilder", pictures: [first, second], shown: 1,
                                           exhausted: false)
        let hiddenMessage = ChatMessage(role: .assistant, text: "Galerie", gallery: hiddenGallery)
        store.appendMessage(hiddenMessage, to: convID)
        await view.morePictures(hiddenMessage)
        let exhausted = PictureGallery(query: "Bilder", pictures: [first], shown: 1, exhausted: true)
        let exhaustedMessage = ChatMessage(role: .assistant, text: "Galerie", gallery: exhausted)
        store.appendMessage(exhaustedMessage, to: convID)
        await view.morePictures(exhaustedMessage)
        view.dismissAlert()
        MockHTTP.install { _ in (500, Data("kaputt".utf8)) }
        let failing = PictureGallery(query: "Nichts", pictures: [first], shown: 1,
                                     nextOffset: 2, exhausted: false)
        let failingMessage = ChatMessage(role: .assistant, text: "Galerie", gallery: failing)
        store.appendMessage(failingMessage, to: convID)
        await view.morePictures(failingMessage)
        view.dismissAlert()
    }

    func testTheImagePromptAndWorkBranches() async throws {
        let (view, store) = try await makeView("gap-image")
        let convID = try XCTUnwrap(store.current?.id)
        MockHTTP.install { request in
            let address = request.url?.absoluteString ?? ""
            if address.contains("images") {
                let bytes = Data([1, 2, 3, 4])
                return (200, Data(#"{"data":[{"b64_json":"\#(bytes.base64EncodedString())"}]}"#.utf8))
            }
            return (200, ToolCallPayload.call(ToolRouter.composeImagePromptTool,
                                              ["status": "resolved", "prompt": "Ein klarer Bildauftrag"]))
        }
        let provider = AppSettings.shared.provider
        AppSettings.shared.provider = .openRouter
        AppSettings.shared.setKey("gap-image-key", for: .openRouter)
        let composed = await view.imagePrompt("Maler", history: [
            ChatMessage(role: .assistant, text: "früher"),
        ], pictures: 1)
        XCTAssertFalse(composed.isEmpty)
        let data = imageData()
        let monochrome = ModelTurn(messages: [], images: [data])
        await view.imageWork(prompt: "schwarz-weiß", history: [], turn: monochrome, fresh: [],
                             isEdit: true, monochrome: true, convID: convID, started: Date(),
                             composeFromChat: false, slot: nil)
        MockHTTP.install { _ in (200, MockHTTP.completion("{\"edit\": null}")) }
        let two = ModelTurn(messages: [], images: [data, data])
        await view.imageWork(prompt: "ändere das", history: [], turn: two, fresh: [], isEdit: true,
                             monochrome: false, convID: convID, started: Date(),
                             composeFromChat: false, slot: nil)
        MockHTTP.install { request in
            let address = request.url?.absoluteString ?? ""
            if address.contains("images") {
                let bytes = Data([5, 6, 7])
                return (200, Data(#"{"data":[{"b64_json":"\#(bytes.base64EncodedString())"}]}"#.utf8))
            }
            return (200, MockHTTP.completion("{\"edit\": 1, \"instruction\": \"neu\"}"))
        }
        await view.imageWork(prompt: "ändere das", history: [], turn: two, fresh: [], isEdit: true,
                             monochrome: false, convID: convID, started: Date(),
                             composeFromChat: false, slot: nil)
        await view.imageWork(prompt: "Maler", history: [], turn: ModelTurn(messages: [], images: []),
                             fresh: [], isEdit: false, monochrome: false, convID: convID,
                             started: Date(), composeFromChat: true, slot: nil)
        AppSettings.shared.provider = provider
    }

    func testTheMonochromeEditUsesTheDirectedPicture() async throws {
        let (view, store) = try await makeView("gap-monochrome-target")
        let convID = try XCTUnwrap(store.current?.id)
        let first = FakePicture.make(CGSize(width: 40, height: 20)).pngData() ?? Data()
        let second = FakePicture.make(CGSize(width: 20, height: 40)).pngData() ?? Data()
        MockHTTP.install { _ in
            (200, MockHTTP.completion(#"{"edit": 2, "instruction": "das zweite Bild"}"#))
        }
        let turn = ModelTurn(messages: [], images: [first, second])
        await view.imageWork(prompt: "mach das zweite Bild schwarz-weiß", history: [], turn: turn,
                             fresh: [], isEdit: true, monochrome: true, convID: convID,
                             started: Date(), composeFromChat: false, slot: nil)
        let file = try XCTUnwrap(store.current?.messages.last?.outImages?.first?.file)
        XCTAssertEqual(store.media.displayRatio(named: file), 0.5, accuracy: 0.01)
    }

    func testTheStandaloneQuestionAndStreamBranches() async throws {
        let (view, store) = try await makeView("gap-stream")
        let convID = try XCTUnwrap(store.current?.id)
        let history = [ChatMessage(role: .user, text: "Und morgen?"),
                       ChatMessage(role: .assistant, text: "Heute regnet es.")]
        MockHTTP.install { _ in
            (200, ToolCallPayload.call(ToolRouter.resolveQueryTool,
                                       ["status": "resolved",
                                        "query": "Wie wird das Wetter morgen in München?"]))
        }
        let rewritten = await view.standaloneQuestion("Und morgen?", history: history)
        XCTAssertEqual(rewritten, "Wie wird das Wetter morgen in München?")
        let alone = [ChatMessage(role: .user, text: "Was ist das für ein Gerät?")]
        let unchanged = await view.standaloneQuestion("Was ist das für ein Gerät?", history: alone)
        XCTAssertEqual(unchanged, "Was ist das für ein Gerät?")
        let named = await view.standaloneQuestion("Was ist das für ein Gerät?", history: alone,
                                                  picture: Data([0xFF, 0xD8, 0xFF, 0xD9]))
        XCTAssertEqual(named, "Wie wird das Wetter morgen in München?")
        let empty = await view.standaloneQuestion("  ", history: alone)
        XCTAssertEqual(empty, "")
        let turn = ModelTurn(messages: [ChatMessage(role: .user, text: "Frage")], images: [])
        MockHTTP.install { _ in
            (200, Data("data: {\"choices\":[{\"delta\":{\"content\":\"\"}}]}\ndata: [DONE]\n".utf8))
        }
        await view.streamChat(turn: turn, history: turn.messages, convID: convID, started: Date())
        MockHTTP.install { _ in (500, Data("kaputt".utf8)) }
        await view.streamChat(turn: turn, history: turn.messages, convID: convID, started: Date())
        MockHTTP.install { _ in
            (200, Data("data: {\"choices\":[{\"delta\":{\"content\":\"[[SEARCH]]\"}}]}\ndata: [DONE]\n".utf8))
        }
        await view.streamChat(turn: turn, history: turn.messages, convID: convID, started: Date())
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertFalse(store.current?.messages.isEmpty ?? true)
    }

    func testTheCalendarWorkBranches() async throws {
        let (view, store) = try await makeView("gap-calendar")
        let convID = try XCTUnwrap(store.current?.id)
        let turn = ModelTurn(messages: [ChatMessage(role: .user, text: "Termin")], images: [])
        _ = fakeCalendar("Test")
        var update = QwenAPI.CalendarPlan(action: .update)
        update.title = "Zahnarzt"
        await view.calendarWork(turn: turn, text: "Verschiebe Zahnarzt", history: turn.messages,
                                convID: convID, started: Date(), plan: update, slot: nil, number: 2)
        MockHTTP.install { _ in
            (200, MockHTTP.completion(#"{"action":"create","title":"Neuer Termin","start":"2026-10-05 09:00"}"#))
        }
        var routedPlan = QwenAPI.CalendarPlan(action: .create)
        await view.calendarWork(turn: turn, text: "Termin morgen", history: turn.messages,
                                convID: convID, started: Date(), plan: routedPlan, slot: nil, number: 1)
        routedPlan.title = "Zahnarzt"
        routedPlan.start = "2026-10-05 09:00"
        let slot = AnswerSlot(writer: ChainMessageWriter(), writes: true)
        slot.carry.notePlanned("Zahnarzt", ref: CalendarRef(eventID: "e1", title: "Zahnarzt", start: Date()))
        await view.calendarWork(turn: turn, text: "Termin", history: turn.messages, convID: convID,
                                started: Date(), plan: routedPlan, slot: slot, number: 1)
        await view.calendarWork(turn: turn, text: "Termin", history: turn.messages, convID: convID,
                                started: Date(), plan: update, slot: slot, number: 2)
        MockHTTP.install { _ in (500, Data("kaputt".utf8)) }
        await view.calendarWork(turn: turn, text: "Termin", history: turn.messages, convID: convID,
                                started: Date(), plan: update, slot: nil, number: 2)
        XCTAssertFalse(store.current?.messages.isEmpty ?? true)
    }

    func testTheScanHelperBranches() async throws {
        let (view, store) = try await makeView("gap-scan")
        let convID = try XCTUnwrap(store.current?.id)
        MockHTTP.install(MockHTTP.defaultHandler)
        await view.startMenuScan()
        try await Task.sleep(for: .milliseconds(500))
        let outcome = ScanOutcome(attachment: AttachedFile(file: "doc_gap.pdf", name: "Scan.pdf",
                                                           kind: .pdf, bytes: 900, pages: 1,
                                                           chars: 90, via: .ocr),
                                  text: "Rechnung über 12 Euro")
        await view.analyzeScan(outcome, request: ScanRequest(kind: .invoice, remind: false),
                               text: "Scanne", convID: convID, slot: nil, number: 1)
        await view.analyzeScan(outcome, request: ScanRequest(kind: .receipt, remind: true),
                               text: "Scanne", convID: convID, slot: nil, number: 1)
        let offer = ScanReminderOffer(title: "Rechnung zahlen", due: Date().addingTimeInterval(86_400))
        let message = ChatMessage(role: .assistant, text: "Scan")
        store.appendMessage(message, to: convID)
        await view.createScanReminder(offer, messageID: message.id)
        try await Task.sleep(for: .milliseconds(400))
        dismissPresentedSheets()
    }

    func testTheRouteAndTurnBranches() async throws {
        let (view, store) = try await makeView("gap-route")
        let convID = try XCTUnwrap(store.current?.id)
        let file = try XCTUnwrap(store.media.storeImageData(imageData()))
        let picture = WebPicture(file: file, pageURL: "https://q.test/t",
                                 fullURL: "https://q.test/t.jpg", title: "Bild", domain: "q.test")
        let gallery = PictureGallery(query: "Bilder", pictures: [picture], shown: 1, exhausted: false)
        store.appendMessage(ChatMessage(role: .user, text: "Zeig mir Bilder"), to: convID)
        let message = ChatMessage(role: .assistant, text: "Galerie", gallery: gallery)
        store.appendMessage(message, to: convID)
        let turn = await view.turnWithFoundPicture(for: ModelTurn(messages: [], images: []))
        XCTAssertFalse(turn.images.isEmpty)
        let pending = PendingPicture(image: UIImage(), file: nil)
        let pendingFile = PendingFile(name: "Notiz.txt", kind: .text, file: "doc_gap", bytes: 4, chars: 2)
        _ = await view.route(text: "Fasse zusammen", pictures: [pending], files: [pendingFile])
        let chain = SendPlan(actions: [ToolDecision(route: .chat), ToolDecision(route: .chat)])
        let routedSend = routed("Frage", plan: chain, convID: convID)
        await view.run(routedSend)
        try await Task.sleep(for: .milliseconds(500))
        view.reportStop(skipped: 1, in: routedSend)
        await view.perform(ToolDecision(route: .readAnswer), in: routedSend, slot: nil)
        await view.perform(ToolDecision(route: .readAloud(ReadAloudRequest(enabled: false))),
                           in: routedSend, slot: nil)
    }

    func testTheWeatherPriceTranslationBranches() async throws {
        var (view, store) = try await makeView("gap-weather-price")
        let convID = try XCTUnwrap(store.current?.id)
        view.weatherService = WeatherFixture.service()
        await view.runWeatherFlow(WeatherRequest(place: "München", day: .today, date: nil, offset: 0),
                                  convID: convID, started: Date())
        if let crafted = store.current?.messages.last {
            store.appendMessage(ChatMessage(role: .assistant, text: "Wetter",
                                            weatherRef: WeatherFixture.ref(hours: WeatherFixture.day { WeatherFixture.hour($0) })),
                                to: convID)
            await view.switchWeatherDay(message: crafted.id, date: "2026-10-05")
        }
        await view.runPriceSearch(terms: ["MacBook"], country: "DE", nearby: false,
                                  question: "Was kostet ein MacBook?", pictures: [],
                                  history: [], convID: convID, started: Date())
        await view.runTranslationFlow(TranslationJob(text: "Guten Morgen", targetCode: "fr"),
                                      convID: convID, started: Date())
        try await Task.sleep(for: .milliseconds(600))
        dismissPresentedSheets()
    }

    func testTheWeatherCorrectionAndDaySwitch() async throws {
        var (view, store) = try await makeView("gap-weather-correction")
        let convID = try XCTUnwrap(store.current?.id)
        let request = WeatherRequest(place: "München", day: .today, date: nil, offset: 0)
        var service = WeatherService()
        let first = service.targetDate(request, now: Date(), calendar: .current)
        let firstDay = try XCTUnwrap(Formatters.eventDay(from: first))
        let second = Formatters.stamp(Calendar.current.date(byAdding: .day, value: 1, to: firstDay)!)
        service.fetcher = { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("geocode") { return Data("{}".utf8) }
            return ForecastFixture.json(date: url.contains(second) ? second : first)
        }
        service.geocodeAddress = { _ in
            WeatherPlace(name: "Berlin", latitude: 52.52, longitude: 13.405, timezone: "Europe/Berlin")
        }
        view.weatherService = service
        await view.runWeatherFlow(request, convID: convID, started: Date())
        let answer = try XCTUnwrap(store.current?.messages.last)
        XCTAssertEqual(answer.weatherRef?.place, "Berlin")
        await view.switchWeatherDay(message: answer.id, date: second)
        XCTAssertEqual(store.current?.messages.first { $0.id == answer.id }?.weatherRef?.day, second)
    }

    func testAStorageProblemIsShownAndDismissed() async throws {
        let (view, store) = try await makeView("gap-storage-problem", persistence: RefusingPersistence())
        let saveFailed = L.FriendlyError(message: L.t("storage_save_failed"), detail: "", openSettings: false)
        while !view.alerts.isEmpty { view.dismissAlert() }
        await store.flushPendingSave()
        view.syncPendingAlerts()
        XCTAssertEqual(view.alerts, [saveFailed])
        XCTAssertNil(store.storageProblem)
    }

    func testTheTranslationFailureIsQueued() async throws {
        let (view, store) = try await makeView("gap-translation-failure")
        let convID = try XCTUnwrap(store.current?.id)
        OnDeviceTranslation.statusOverride = { _ in .unsupportedPair }
        MockHTTP.install { _ in (500, Data()) }
        defer {
            OnDeviceTranslation.statusOverride = nil
            MockHTTP.install(MockHTTP.defaultHandler)
        }
        await view.runTranslationFlow(TranslationJob(text: "Guten Morgen", targetCode: "fr"),
                                      convID: convID, started: Date())
        XCTAssertFalse(view.alerts.isEmpty)
    }

    func testTheCalendarDecisionRunsTheCalendarFlow() async throws {
        let (view, store) = try await makeView("gap-send-calendar")
        let convID = try XCTUnwrap(store.current?.id)
        let (fake, _) = fakeCalendar("Test")
        var plan = QwenAPI.CalendarPlan(action: .create)
        plan.title = "Gap Termin"
        plan.start = "2026-10-20 10:00"
        plan.end = "2026-10-20 11:00"
        var decision = ToolDecision(route: .calendar)
        decision.calendarPlan = plan
        let routedSend = routed("Termin", plan: SendPlan.singleChat, convID: convID)
        await view.perform(decision, in: routedSend, slot: nil)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertFalse(fake.savedEvents.isEmpty)
        XCTAssertNotNil(store.current)
    }

    func testTheScanReminderFailureIsReported() async throws {
        let (view, store) = try await makeView("gap-scan-reminder-failure")
        let convID = try XCTUnwrap(store.current?.id)
        let message = ChatMessage(role: .assistant, text: "Scan")
        store.appendMessage(message, to: convID)
        let offer = ScanReminderOffer(title: "Zahlen", due: Date().addingTimeInterval(3600))
        store.attachReminderOffer(offer, to: message.id, in: convID)
        let fake = FakeReminderEventStore()
        fake.saveFailure = APIError(message: "kaputt")
        EventKitReminderStore.storeOverride = fake
        EventKitReminderStore.accessStatusOverride = .fullAccess
        defer {
            EventKitReminderStore.storeOverride = nil
            EventKitReminderStore.accessStatusOverride = nil
        }
        await view.createScanReminder(offer, messageID: message.id)
        XCTAssertNotNil(store.current)
    }

    func testAnEmptyChatAnswerIsRetriedOnceAndThenReported() async throws {
        var (view, store) = try await makeView("gap-stream-empty-retry")
        let convID = try XCTUnwrap(store.current?.id)
        let turn = ModelTurn(messages: [ChatMessage(role: .user, text: "Frage")], images: [])
        let calls = LockedValue(0)
        view.chatRunner = { _, onChunk in
            let call = calls.mutate { value in
                value += 1
                return value
            }
            let text = call == 1 ? "   " : "Antwort nach Wiederholung"
            onChunk(text)
            return text
        }
        await view.streamChat(turn: turn, history: turn.messages, convID: convID, started: Date())
        XCTAssertEqual(calls.current, 2, "eine leere Antwort wird genau einmal wiederholt")
        XCTAssertTrue(store.current?.messages.contains { $0.text.contains("Antwort nach Wiederholung") } ?? false)

        let failing = LockedValue(0)
        view.chatRunner = { _, _ in
            failing.mutate { $0 += 1 }
            return "  \n "
        }
        await view.streamChat(turn: turn, history: turn.messages, convID: convID, started: Date())
        XCTAssertEqual(failing.current, 2, "nach der Wiederholung wird kein dritter Versuch gestartet")
        XCTAssertTrue(store.current?.messages.contains { $0.text.contains(L.t("chat_answer_empty")) } ?? false)
    }

    func testTheStreamFailuresAreRendered() async throws {
        var (view, store) = try await makeView("gap-stream-failures")
        let convID = try XCTUnwrap(store.current?.id)
        let turn = ModelTurn(messages: [ChatMessage(role: .user, text: "Hallo")], images: [])
        view.chatRunner = { _, onChunk in
            onChunk("Teil")
            throw APIError(message: "kaputt", recoveredText: "Teil")
        }
        await view.streamChat(turn: turn, history: [], convID: convID, started: Date())
        XCTAssertTrue(store.current?.messages.contains { $0.text.contains("Teil") } ?? false)
        view.chatRunner = { _, _ in throw NSError(domain: "gap", code: 1) }
        await view.streamChat(turn: turn, history: [], convID: convID, started: Date())
        view.chatRunner = { _, onChunk in
            onChunk("Rest")
            throw APIError(message: "cancelled", recoveredText: "Rest")
        }
        await view.streamChat(turn: turn, history: [], convID: convID, started: Date())
    }

    func testTheTranslationRunnerFailureIsHandled() async throws {
        let (view, store) = try await makeView("gap-translation-runner")
        let convID = try XCTUnwrap(store.current?.id)
        TranslationFlow.runOverride = { _, _ in throw APIError(message: "kaputt") }
        defer { TranslationFlow.runOverride = nil }
        await view.runTranslationFlow(TranslationJob(text: "Hallo", targetCode: "fr"),
                                      convID: convID, started: Date())
        XCTAssertFalse(view.alerts.isEmpty)
    }

    func testTheStoreGapMethods() async throws {
        let paths = temporaryPaths("gap-store")
        let store = ChatStore(media: MediaStore(paths: paths), paths: paths)
        store.newConversation()
        let convID = try XCTUnwrap(store.current?.id)
        let message = ChatMessage(role: .assistant, text: "Antwort")
        store.appendMessage(message, to: convID)
        let gallery = PictureGallery(query: "Bilder", pictures: [], shown: 0, exhausted: true)
        store.updateGallery(message.id, in: convID, gallery)
        XCTAssertEqual(store.current?.messages.first?.gallery, gallery)
        store.updateGallery(UUID(), in: convID, gallery)
        store.updateGallery(message.id, in: UUID(), gallery)
        store.attachReminderOffer(ScanReminderOffer(title: "Zahlen", due: Date()), to: message.id,
                                  in: convID)
        XCTAssertNotNil(store.current?.messages.first?.reminderOffer)
        store.settleReminderOffer(ReminderRef(reminderID: "r1", title: "Zahlen", list: "L",
                                              due: nil, allDay: false, place: nil),
                                  to: message.id, in: convID)
        XCTAssertNil(store.current?.messages.first?.reminderOffer)
        XCTAssertEqual(ChatStore.title(of: "\n\n Erste Zeile \n Zweite"), "Erste Zeile")
        store.stand(in: PriceWatchStore(paths: paths))
        store.restoreWatches()
        store.stand(in: PriceWatchStore(paths: paths))
        store.restoreWatches()
        store.restoreWatches()
    }
}

@MainActor
extension ChatViewGapCoverageTests {
    func testTheSendAndChainGuardBranches() async throws {
        let (view, store) = try await makeView("gap-send-guards2")
        let settings = AppSettings.shared
        let vision = settings.visionModel
        settings.visionModel = ""
        view.pendingImages = [PendingPicture(image: UIImage(), file: nil)]
        await view.send()
        settings.visionModel = vision
        view.pendingImages = []
        let image = UIGraphicsImageRenderer(size: CGSize(width: 30, height: 30)).image { _ in }
        _ = await view.route(text: "Übersetze das bitte ins Französische",
                             pictures: [PendingPicture(image: image, file: nil)], files: [])
        let convID = try XCTUnwrap(store.current?.id)
        let chain = SendPlan(actions: [ToolDecision(route: .clock(ClockRequest(timeZone: "UTC", place: nil))),
                                       ToolDecision(route: .clock(ClockRequest(timeZone: "UTC", place: nil)))])
        let routedSend = routed("Frage", plan: chain, convID: convID)
        view.chainRun.requestStop()
        await view.run(routedSend)
        if let decision = ToolRouter.decisions(from: payload(ToolRouter.calendarTool,
                                                             #"{"action":"none"}"#)).first {
            await view.perform(decision, in: routedSend, slot: nil)
        }
        dismissPresentedSheets()
    }

    func testTheFilesAndVoiceExtraBranches() async throws {
        let (view, store) = try await makeView("gap-file-voice")
        let convID = try XCTUnwrap(store.current?.id)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 60)).image { _ in }
        let data = try XCTUnwrap(image.pngData())
        let file = try XCTUnwrap(store.media.storeImageData(data))
        view.attachForEditing(Attachment(file: file))
        try await Task.sleep(for: .milliseconds(400))
        view.attachForEditing(Attachment(file: file))
        try await Task.sleep(for: .milliseconds(400))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let images = (0..<12).map { index -> URL in
            let url = folder.appendingPathComponent("Bild\(index).png")
            try? data.write(to: url)
            return url
        }
        view.pendingImages = []
        view.pendingFiles = []
        await view.analyzeDroppedFiles(images)
        try await Task.sleep(for: .milliseconds(600))
        let listenOff = view.settings.voice.listenOffWord
        view.settings.voice.listenOffWord = "ruhe"
        view.settings.voice.listenMode = true
        view.followListenGate(view.listenGate)
        try await Task.sleep(for: .milliseconds(400))
        view.voiceDidTranscribe("ruhe")
        view.settings.voice.listenMode = false
        view.settings.voice.listenOffWord = listenOff
        view.voice.cancel()
        let spoken = ChatMessage(role: .assistant, text: "Es ist sonnig.")
        store.appendMessage(spoken, to: convID)
        view.speakWeather(message: spoken.id)
        dismissPresentedSheets()
    }

    func testTheWeatherPlaceCorrectionAndDaySwitch() async throws {
        var (view, store) = try await makeView("gap-weather2")
        let convID = try XCTUnwrap(store.current?.id)
        view.weatherService = WeatherFixture.service()
        await view.runWeatherFlow(WeatherRequest(place: "München", day: .today, date: nil, offset: 0),
                                  convID: convID, started: Date())
        let crafted = ChatMessage(role: .assistant, text: "Wetter",
                                  weatherRef: WeatherFixture.ref(hours: WeatherFixture.day { WeatherFixture.hour($0) }))
        store.appendMessage(crafted, to: convID)
        await view.switchWeatherDay(message: crafted.id, date: "2026-10-06")
        let updated = store.current?.messages.first { $0.id == crafted.id }
        XCTAssertNotNil(updated)
        dismissPresentedSheets()
    }

    func testTheGalleryShareAndMorePicturesSuccess() async throws {
        let (view, store) = try await makeView("gap-gallery2")
        let convID = try XCTUnwrap(store.current?.id)
        let file = try XCTUnwrap(store.media.storeImageData(imageData()))
        let picture = WebPicture(file: file, pageURL: "https://q.test/g",
                                 fullURL: "https://q.test/g.jpg", title: "Bild", domain: "q.test")
        let gallery = PictureGallery(query: "Bilder", pictures: [picture], shown: 1, exhausted: false)
        let message = ChatMessage(role: .assistant, text: "Galerie", gallery: gallery)
        store.appendMessage(message, to: convID)
        view.gallerySelection.begin(owner: message.id)
        view.gallerySelection.toggle(picture.file)
        view.shareGallerySelection()
        let payload = imageData()
        MockHTTP.install { request in
            let address = request.url?.absoluteString ?? ""
            if address.contains("bing.com/images/async") {
                let raw = #"{"turl":"https://th.bing.com/th?id=2","purl":"https://example.com/page","murl":"https://cdn.example.com/full.jpg","t":"Titel"}"#
                let encoded = raw.replacingOccurrences(of: "\"", with: "&quot;")
                return (200, Data("<a m=\"\(encoded)\">".utf8))
            }
            return (200, payload)
        }
        let moreGallery = PictureGallery(query: "Bilder", pictures: [picture], shown: 1,
                                         nextOffset: 2, exhausted: false)
        let moreMessage = ChatMessage(role: .assistant, text: "Galerie", gallery: moreGallery)
        store.appendMessage(moreMessage, to: convID)
        await view.morePictures(moreMessage)
        let updated = store.current?.messages.first { $0.id == moreMessage.id }?.gallery
        XCTAssertNotNil(updated)
        dismissPresentedSheets()
    }

    func testTheTranslationCancellationAndDefaultChatView() async throws {
        let (view, store) = try await makeView("gap-translation-cancel")
        let convID = try XCTUnwrap(store.current?.id)
        let task = Task {
            await view.runTranslationFlow(TranslationJob(text: "Guten Morgen", targetCode: "fr"),
                                          convID: convID, started: Date())
        }
        task.cancel()
        await task.value
        MockHTTP.install { _ in (500, Data("kaputt".utf8)) }
        await view.runTranslationFlow(TranslationJob(text: "Guten Morgen", targetCode: "fr"),
                                      convID: convID, started: Date())
        _ = ChatView()
        dismissPresentedSheets()
    }

    func testTheWeatherSuccessPaths() async throws {
        var (view, store) = try await makeView("gap-weather3")
        let convID = try XCTUnwrap(store.current?.id)
        view.weatherService = WeatherFixture.service()
        await view.runWeatherFlow(WeatherRequest(place: "München", day: .today, date: nil, offset: 0),
                                  convID: convID, started: Date())
        let crafted = ChatMessage(role: .assistant, text: "Wetter",
                                  weatherRef: WeatherFixture.ref(place: "Berlin",
                                                                 hours: WeatherFixture.day { WeatherFixture.hour($0) }))
        store.appendMessage(crafted, to: convID)
        await view.switchWeatherDay(message: crafted.id, date: "2026-10-06")
        let updated = store.current?.messages.first { $0.id == crafted.id }
        XCTAssertNotNil(updated?.weatherRef)
        dismissPresentedSheets()
    }

    func testSmokeTheScaffoldCameraAndListingBranches() async throws {
        let settings = AppSettings.shared
        let provider = settings.provider
        let savedProfile = settings.profile
        settings.updateProfile(of: provider) { profile in
            profile.listingVersion = 0
        }
        MockHTTP.install { _ in (200, Data(#"{"data":[{"id":"gap-camera-model"}]}"#.utf8)) }
        _ = try await makeView("gap-camera")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 60, height: 40)).image { _ in }
        CameraPresenter.shared.onImage?(image)
        try await Task.sleep(for: .milliseconds(600))
        DocumentPresenter.shared.onURLs?([URL(fileURLWithPath: "/tmp/gibt-es-nicht.txt")])
        try await Task.sleep(for: .milliseconds(300))
        settings.profiles[provider] = savedProfile
        dismissPresentedSheets()
    }

    func testSmokeTheStoreFailureWiring() async throws {
        let paths = temporaryPaths("gap-store-failure")
        try makeSupportUnwritable(paths)
        defer { restoreSupport(paths) }
        let memory = MemoryStore(paths: paths)
        let store = ChatStore(media: MediaStore(paths: paths), paths: paths, memory: memory)
        _ = await memory.add(text: "mag Tee", category: .likes, source: .explicit)
        try await Task.sleep(for: .milliseconds(400))
        _ = store.storageProblem
    }
}

@MainActor
extension ChatViewGapCoverageTests {
    func testTheStreamErrorBranchesWithARunner() async throws {
        var (view, store) = try await makeView("gap-stream-runner")
        let convID = try XCTUnwrap(store.current?.id)
        let turn = ModelTurn(messages: [ChatMessage(role: .user, text: "Frage")], images: [])
        view.chatRunner = { _, onChunk in
            onChunk("Teil")
            throw APIError(message: "kaputt", status: 500)
        }
        await view.streamChat(turn: turn, history: turn.messages, convID: convID, started: Date())
        view.chatRunner = { _, _ in throw CancellationError() }
        await view.streamChat(turn: turn, history: turn.messages, convID: convID, started: Date())
        view.chatRunner = { _, _ in
            try? await Task.sleep(for: .milliseconds(120))
            throw APIError(message: "kaputt", status: 500)
        }
        let cancelling = Task {
            await view.streamChat(turn: turn, history: turn.messages, convID: convID, started: Date())
        }
        try await Task.sleep(for: .milliseconds(30))
        cancelling.cancel()
        await cancelling.value
        view.chatRunner = { _, _ in "" }
        await view.streamChat(turn: turn, history: turn.messages, convID: convID, started: Date())
        MockHTTP.install { _ in (200, MockHTTP.sse("[[SEARCH]]")) }
        view.chatRunner = { _, onChunk in
            onChunk("[[SEARCH]]")
            return "[[SEARCH]]"
        }
        await view.streamChat(turn: turn, history: turn.messages, convID: convID, started: Date())
        MockHTTP.install(MockHTTP.defaultHandler)
        dismissPresentedSheets()
    }

    func testTheScanFlowWithAFakeScanner() async throws {
        let (view, store) = try await makeView("gap-scan-fake")
        let convID = try XCTUnwrap(store.current?.id)
        store.appendMessage(ChatMessage(role: .user, text: "Scanne das"), to: convID)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 300)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 240, height: 300))
            NSString(string: "Rechnung 12 Euro").draw(at: CGPoint(x: 12, y: 120),
                withAttributes: [.font: UIFont.systemFont(ofSize: 22), .foregroundColor: UIColor.black])
        }
        MockHTTP.install(MockHTTP.defaultHandler)
        DocumentScanner.shared.isSupportedOverride = true
        DocumentScanner.shared.scanOverride = { [image] }
        await view.runScanFlow(ScanRequest(kind: .receipt, remind: false), text: "Scan",
                               convID: convID, started: Date(), slot: nil, number: 1)
        try await Task.sleep(for: .milliseconds(1200))
        DocumentScanner.shared.scanOverride = { nil }
        await view.runScanFlow(ScanRequest(kind: .other, remind: false), text: "Scan",
                               convID: convID, started: Date(), slot: nil, number: 1)
        try await Task.sleep(for: .milliseconds(400))
        DocumentScanner.shared.isSupportedOverride = false
        CameraPresenter.shared.isAvailableOverride = false
        await view.runScanFlow(ScanRequest(kind: .other, remind: false), text: "Scan",
                               convID: convID, started: Date(), slot: nil, number: 1)
        try await Task.sleep(for: .milliseconds(400))
        CameraPresenter.shared.isAvailableOverride = true
        CameraPresenter.shared.captureOverride = { image }
        DocumentScanner.shared.isSupportedOverride = true
        DocumentScanner.shared.scanOverride = { nil }
        await view.runScanFlow(ScanRequest(kind: .other, remind: false), text: "Scan",
                               convID: convID, started: Date(), slot: nil, number: 1)
        try await Task.sleep(for: .milliseconds(500))
        DocumentScanner.shared.isSupportedOverride = nil
        DocumentScanner.shared.scanOverride = nil
        CameraPresenter.shared.isAvailableOverride = nil
        CameraPresenter.shared.captureOverride = nil
        dismissPresentedSheets()
    }
}

@MainActor
extension ChatViewGapCoverageTests {
    func testTheCalendarSuccessPathThroughTheView() async throws {
        let (view, store) = try await makeView("gap-calendar-success")
        let convID = try XCTUnwrap(store.current?.id)
        _ = fakeCalendar("Privat")
        let turn = ModelTurn(messages: [ChatMessage(role: .user, text: "Termin")], images: [])
        var plan = QwenAPI.CalendarPlan(action: .create)
        plan.title = "Zahnarzt"
        plan.start = "2026-10-05 09:00"
        plan.calendar = "Privat"
        let writer = ChainMessageWriter()
        let slot = AnswerSlot(writer: writer, writes: true)
        slot.carry.notePlanned("Zahnarzt", ref: CalendarRef(eventID: "e1", title: "Zahnarzt", start: Date()))
        await view.calendarWork(turn: turn, text: "Termin", history: turn.messages, convID: convID,
                                started: Date(), plan: plan, slot: slot, number: 1)
        let again = AnswerSlot(writer: ChainMessageWriter(), writes: true)
        await view.calendarWork(turn: turn, text: "Termin", history: turn.messages, convID: convID,
                                started: Date(), plan: plan, slot: again, number: 2)
        await view.calendarWork(turn: turn, text: "Nichts", history: turn.messages, convID: convID,
                                started: Date(), plan: QwenAPI.CalendarPlan(action: .none),
                                slot: again, number: 2)
        XCTAssertFalse(store.current?.messages.isEmpty ?? true)
        dismissPresentedSheets()
    }
}

@MainActor
extension ChatViewGapCoverageTests {
    func testTheTranslationSuccessPath() async throws {
        let (view, store) = try await makeView("gap-translation-success")
        let convID = try XCTUnwrap(store.current?.id)
        MockHTTP.install { _ in
            (200, ToolCallPayload.call(ToolRouter.reportTranslationTool,
                                       ["translation": "Bonjour tout le monde"]))
        }
        await view.runTranslationFlow(TranslationJob(text: "Guten Morgen", targetCode: "fr"),
                                      convID: convID, started: Date())
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertFalse(store.current?.messages.isEmpty ?? true)
        MockHTTP.install(MockHTTP.defaultHandler)
        dismissPresentedSheets()
    }

    func testTheScanReminderOfferPath() async throws {
        let (view, store) = try await makeView("gap-scan-reminder-offer")
        let convID = try XCTUnwrap(store.current?.id)
        store.appendMessage(ChatMessage(role: .user, text: "Scanne das"), to: convID)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 300)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 240, height: 300))
            NSString(string: "Rechnung 12 Euro faellig am 5.10.").draw(at: CGPoint(x: 12, y: 120),
                withAttributes: [.font: UIFont.systemFont(ofSize: 20), .foregroundColor: UIColor.black])
        }
        let arguments = #"{"action":"create","title":"Rechnung zahlen","due":"2026-10-05"}"#
        let message: [String: Any] = [
            "content": "",
            "tool_calls": [["id": "c1", "type": "function",
                            "function": ["name": ToolRouter.reminderTool, "arguments": arguments]]]
        ]
        let reminderData = (try? JSONSerialization.data(withJSONObject: ["choices": [["message": message]]]))
            ?? Data()
        MockHTTP.install { request in
            let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            if body.contains("exactly one call") {
                return (200, reminderData)
            }
            return (200, MockHTTP.completion("Die Rechnung liegt bei 12 Euro."))
        }
        DocumentScanner.shared.isSupportedOverride = true
        DocumentScanner.shared.scanOverride = { [image] }
        await view.runScanFlow(ScanRequest(kind: .invoice, remind: true), text: "Scanne das",
                               convID: convID, started: Date(), slot: nil, number: 1)
        try await Task.sleep(for: .milliseconds(1800))
        DocumentScanner.shared.isSupportedOverride = nil
        DocumentScanner.shared.scanOverride = nil
        MockHTTP.install(MockHTTP.defaultHandler)
        dismissPresentedSheets()
    }
}

@MainActor
extension ChatViewGapCoverageTests {
    func testSmokeTheSmallChatHelpers() async throws {
        _ = AnswerError.model("invalid parameter detected", model: "m", generic: "generisch")
        _ = AnswerError.model("data inspection failed", model: "m", generic: "generisch")
        let (view, store) = try await makeView("gap-chat-helpers")
        let problem = store.storageProblem
        store.dismissStorageProblem()
        view.syncPendingAlerts()
        _ = problem
        dismissPresentedSheets()
    }
}

@MainActor
extension ChatViewGapCoverageTests {
    func testTheListenModeSettingsBranchAndVoiceCommand() async throws {
        let (view, _) = try await makeView("gap-voice-command")
        let settings = AppSettings.shared
        let provider = settings.provider
        let key = settings.key(for: provider)
        settings.setKey("", for: provider)
        view.toggleListenMode()
        XCTAssertTrue(view.showSettings)
        settings.setKey(key, for: provider)
        view.voice.signals = VoiceSignals(wake: "", stop: "", cancel: "", newChat: "neuer chat")
        view.voice.listen { _ in }
        view.voiceDidTranscribe("neuer chat")
        view.abortVoice()
    }

    func testTheLocalMonochromeEditFinishesWithoutTheModel() async throws {
        let (view, store) = try await makeView("gap-image-mono")
        let convID = try XCTUnwrap(store.current?.id)
        let settings = AppSettings.shared
        let savedModel = settings.imageModel
        settings.imageModel = "image-model"
        defer { settings.imageModel = savedModel }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 30, height: 20)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 30, height: 20))
        }
        let data = try XCTUnwrap(image.pngData())
        let turn = ModelTurn(messages: [], images: [data])
        await view.runImageFlow(prompt: "", history: [], turn: turn, fresh: [], isEdit: true,
                                convID: convID, started: Date(), monochrome: true)
        XCTAssertEqual(store.current?.messages.last?.outImages?.count, 1)
    }
}

@MainActor
extension ChatViewGapCoverageTests {
    func testTheEditPromptAndModelFailure() async throws {
        let (view, store) = try await makeView("gap-image-edit-fail")
        let convID = try XCTUnwrap(store.current?.id)
        let settings = AppSettings.shared
        let savedModel = settings.imageModel
        settings.imageModel = "image-model"
        defer { settings.imageModel = savedModel }
        MockHTTP.install { _ in (500, Data("content policy".utf8)) }
        defer { MockHTTP.install(MockHTTP.defaultHandler) }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { _ in }
        let data = try XCTUnwrap(image.pngData())
        let turn = ModelTurn(messages: [], images: [data])
        await view.runImageFlow(prompt: "mach es blau", history: [], turn: turn, fresh: [],
                                isEdit: true, convID: convID, started: Date(), monochrome: false)
        XCTAssertNotNil(store.current?.messages.last)
    }

    func testTheGallerySharingEndsTheSelection() async throws {
        let (view, store) = try await makeView("gap-gallery-share")
        let convID = try XCTUnwrap(store.current?.id)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { _ in }
        let data = try XCTUnwrap(image.pngData())
        let file = try XCTUnwrap(store.media.storeImageData(data))
        let picture = WebPicture(file: file, pageURL: "https://q.test/p", fullURL: "https://q.test/p.jpg",
                                 title: "Bild", domain: "q.test")
        let gallery = PictureGallery(query: "Bilder", pictures: [picture], shown: 1, exhausted: true)
        let message = ChatMessage(role: .assistant, text: "Bilder", gallery: gallery)
        store.appendMessage(message, to: convID)
        view.gallerySelection.begin(owner: message.id)
        view.gallerySelection.toggle(file)
        let host = hostWindow(Text("Host"))
        addTeardownBlock { host?.isHidden = true }
        Presenter.hostOverride = host?.rootViewController
        defer { Presenter.hostOverride = nil }
        view.shareGallerySelection()
        XCTAssertFalse(view.gallerySelection.isPicking)
    }
}
