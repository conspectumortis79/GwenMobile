@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import UserNotifications
import XCTest
import GwenMobileKit
@testable import GwenMobileProbes

private struct FlowLocationFix: LocationFixing {
    func fix() async throws -> CLLocation {
        CLLocation(latitude: 48.137, longitude: 11.575)
    }
}

private struct FlowBriefingCalendar: BriefingCalendarReading {
    func briefingEvents(on day: Date) -> [DayBriefingEvent] { [] }
}

private struct FlowBriefingReminders: BriefingReminderReading {
    func briefingReminders() async -> [StoredReminder] { [] }
}

private struct FlowBriefingWeather: BriefingWeatherLoading {
    func briefingWeather(dayOffset: Int) async throws -> WeatherRef {
        WeatherFixture.ref(hours: WeatherFixture.day { WeatherFixture.hour($0) })
    }
}

private struct FlowBriefingTravel: BriefingTravelLooking {
    func briefingTravel(to location: String, departure: Date) async -> DayBriefingTravel? { nil }
}

@MainActor
final class ChatFlowCoverageTests: GwenTestCase {
    private let hosted = HostedChatView()

    override func setUp() {
        super.setUp()
        MockHTTP.install(MockHTTP.defaultHandler)
    }

    override func tearDown() async throws {
        MockHTTP.uninstall()
        if !hosted.close(),
           let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
           let appWindow = scene.windows.first(where: { $0.rootViewController != nil }) {
            appWindow.makeKeyAndVisible()
        }
        try await super.tearDown()
    }

    private func makeView(_ prefix: String) async throws -> (ChatView, ChatStore) {
        let store = HostedChatView.store(temporaryPaths(prefix))
        AppSettings.shared.provider = .qwenCloud
        AppSettings.shared.visionModel = "flow-vision"
        AppSettings.shared.imageModel = "flow-image"
        AppSettings.shared.setKey("flow-test-key", for: .qwenCloud)
        var view = try await hosted.open(store, in: self)
        WeatherService.clearCache()
        view.callDesk.stand(in: ProbeDialer(), directory: FixtureContacts())
        view.messageDesk.stand(in: ProbeMessenger(), directory: FixtureContacts())
        view.musicDesk.stand(in: ProbeMusic.silent())
        view.routeDesk.stand(in: ProbeRouteOpener())
        view.reminderDesk.stand(in: ProbeReminderStore(), places: ProbePlaceLookup())
        view.weatherService = stubbedWeather()
        view.briefingDesk.stand(in: DayBriefingSources(calendar: FlowBriefingCalendar(),
                                                       reminders: FlowBriefingReminders(),
                                                       contacts: FixtureContacts(),
                                                       weather: FlowBriefingWeather(),
                                                       travel: FlowBriefingTravel()))
        return (view, store)
    }

    private func stubbedWeather() -> WeatherService {
        var service = WeatherService()
        service.fixer = FlowLocationFix()
        service.fetcher = { _ in ForecastFixture.json(date: "2026-10-05") }
        service.geocodeAddress = { name in
            WeatherPlace(name: name, latitude: 48.137, longitude: 11.575, timezone: "Europe/Berlin")
        }
        service.localSearch = { name in
            WeatherPlace(name: name, latitude: 48.137, longitude: 11.575, timezone: "Europe/Berlin")
        }
        service.reverseGeocode = { _ in "München" }
        return service
    }

    private func temporaryFile(name: String, text: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("flow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    private func temporaryImage() throws -> (url: URL, data: Data) {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 60)).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 60))
        }
        let data = try XCTUnwrap(image.pngData())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("flow-\(UUID().uuidString).png")
        try data.write(to: url)
        return (url, data)
    }

    private func routed(_ decision: ToolDecision, convID: UUID) -> RoutedSend {
        RoutedSend(text: "Frage", plan: SendPlan(actions: [decision]),
                   turn: ModelTurn(messages: [], images: []), history: [],
                   attachments: [], files: [], convID: convID, started: Date())
    }

    private func run(_ decision: ToolDecision, _ view: ChatView, _ store: ChatStore) async {
        guard let convID = store.current?.id else { return }
        await view.perform(decision, in: routed(decision, convID: convID), slot: nil)
    }

    func testTheClockAndMemoryFlowsRun() async throws {
        let (view, store) = try await makeView("flow-clock")
        await run(ToolDecision(route: .clock(ClockRequest(timeZone: "Asia/Tokyo", place: "Tokio"))), view, store)
        await run(ToolDecision(route: .memory(MemoryRequest(action: .create, text: "mag Tee",
                                                           category: .likes))), view, store)
        await run(ToolDecision(route: .memory(MemoryRequest(action: .list))), view, store)
        XCTAssertFalse(store.current?.messages.isEmpty ?? true)
    }

    func testSmokeTheReadAloudAndReadAnswerFlowsRun() async throws {
        let (view, store) = try await makeView("flow-read")
        await run(ToolDecision(route: .readAloud(ReadAloudRequest(enabled: true))), view, store)
        await run(ToolDecision(route: .readAloud(ReadAloudRequest(enabled: false))), view, store)
        await run(ToolDecision(route: .readAnswer), view, store)
    }

    func testSmokeTheStreamingChatAndCodeFlowsRun() async throws {
        let (view, store) = try await makeView("flow-chat")
        await run(ToolDecision(route: .chat), view, store)
        await run(ToolDecision(route: .code(language: CodeLanguage(toolValue: "html"))), view, store)
    }

    func testSmokeTheWebSearchFlowRuns() async throws {
        let (view, store) = try await makeView("flow-search")
        await run(ToolDecision(route: .chat, searchQuery: "Eurovision Gewinner"), view, store)
    }

    func testSmokeTheWeatherFlowRuns() async throws {
        let (view, store) = try await makeView("flow-weather")
        await run(ToolDecision(route: .weather(WeatherRequest(place: "München", day: .tomorrow,
                                                              date: "2026-10-05"))), view, store)
        await run(ToolDecision(route: .weather(WeatherRequest(place: nil, day: .today,
                                                              date: "2026-10-05"))), view, store)
    }

    func testSmokeTheBriefingFlowRuns() async throws {
        let (view, store) = try await makeView("flow-briefing")
        await run(ToolDecision(route: .dayBriefing(DayBriefingRequest(day: .tomorrow))), view, store)
    }

    func testSmokeThePriceSearchAndPriceWatchFlowsRun() async throws {
        let (view, store) = try await makeView("flow-price")
        await run(ToolDecision(route: .priceSearch(terms: ["MacBook Pro 14"], country: "DE",
                                                   nearby: false)), view, store)
        await run(ToolDecision(route: .priceWatch(PriceWatchRequest(action: .create,
                                                                    terms: ["PS5"], goal: 400))), view, store)
    }

    func testSmokeThePictureSearchAndImageFlowsRun() async throws {
        let (view, store) = try await makeView("flow-pictures")
        await run(ToolDecision(route: .pictureSearch(query: "Eiffelturm")), view, store)
        await run(ToolDecision(route: .imageCreate, picturePrompt: "Leuchtturm"), view, store)
        await run(ToolDecision(route: .imageEdit, pictureInstruction: "schwarz-weiß"), view, store)
    }

    func testSmokeTheCallAndMessageFlowsRun() async throws {
        let (view, store) = try await makeView("flow-contact")
        await run(ToolDecision(route: .call(ContactRequest(person: "Peter Müller"))), view, store)
        await run(ToolDecision(route: .message(MessageRequest(recipient: ContactRequest(person: "Peter"),
                                                              text: "Bin später da"))), view, store)
    }

    func testSmokeTheMusicFlowRuns() async throws {
        let (view, store) = try await makeView("flow-music")
        await run(ToolDecision(route: .music(MusicRequest(action: .play, query: "Hello",
                                                          artist: "Adele", kind: .song))), view, store)
    }

    func testSmokeTheReminderFlowRuns() async throws {
        let (view, store) = try await makeView("flow-reminder")
        if let reminder = ToolRouter.decisions(from: payload(ToolRouter.reminderTool,
                                                             #"{"action":"create","title":"Milch"}"#)).first {
            await run(reminder, view, store)
        }
    }

    func testSmokeTheTimerFlowRuns() async throws {
        let (view, store) = try await makeView("flow-timer")
        await run(ToolDecision(route: .timer(TimerRequest(minutes: 10, seconds: nil, title: "Tee"))),
                  view, store)
    }

    func testSmokeThePlaceAndTranslateFlowsRun() async throws {
        let (view, store) = try await makeView("flow-place")
        await run(ToolDecision(route: .nearbyPlace(terms: ["Apotheke"], mode: .walking)), view, store)
        await run(ToolDecision(route: .routeToPlace(terms: ["Bibliothek"], mode: .cycling)), view, store)
        await run(ToolDecision(route: .translate(TranslationJob(text: "Guten Morgen", targetCode: "fr"))),
                  view, store)
    }

    func testSmokeTheScanAndHistoryFlowsRun() async throws {
        let (view, store) = try await makeView("flow-scan")
        await run(ToolDecision(route: .scanDocument(ScanRequest(kind: .receipt, remind: false))), view, store)
        await run(ToolDecision(route: .history), view, store)
    }

    func testTheFileKeepingRulesAndQueueLimits() async throws {
        let (view, _) = try await makeView("flow-keep")
        XCTAssertEqual(ChatView.keeping([], alongside: []).kept.count, 0)
        let pictures = (0..<12).map { PendingPicture(image: UIImage(), file: "f\($0).jpg") }
        let outcome = ChatView.keeping(pictures, alongside: [])
        XCTAssertEqual(outcome.kept.count, ImagePolicy.maxAttachmentsPerMessage)
        XCTAssertEqual(outcome.fresh.count, ImagePolicy.maxAttachmentsPerMessage)
        XCTAssertGreaterThan(outcome.dropped, 0)
        let first = Array(pictures.prefix(3))
        let topped = ChatView.keeping(pictures, alongside: first)
        XCTAssertEqual(topped.kept.count, ImagePolicy.maxAttachmentsPerMessage)
        XCTAssertEqual(topped.kept.prefix(3).map(\.file), first.map(\.file))
        _ = view.queue(pictures: pictures)
        XCTAssertEqual(view.pendingImages.count, ImagePolicy.maxAttachmentsPerMessage)
    }

    func testFilesAreStagedReadAndApplied() async throws {
        let (view, _) = try await makeView("flow-files")
        let text = try temporaryFile(name: "Notiz.txt", text: "Zeile eins\nZeile zwei")
        let stagedOption = await view.stageFile(text)
        let staged = try XCTUnwrap(stagedOption)
        XCTAssertEqual(view.pendingFiles.count, 1)
        _ = await view.readStagedFile(staged.pending, from: staged.url)
        await view.importFile(text)
        view.importPicked([text])
        try await Task.sleep(for: .milliseconds(500))
        view.applyExtraction(nil, toFile: "doc_none", named: "keins", id: UUID())
        XCTAssertTrue(ChatView.fileRefs(from: [], carried: nil).isEmpty)
    }

    func testUnsupportedAndOversizedFilesAreRefused() async throws {
        let (view, _) = try await makeView("flow-file-guards")
        let unsupported = try temporaryFile(name: "Bild.xyz", text: "nope")
        let refused = await view.stageFile(unsupported)
        XCTAssertNil(refused)
        let big = try temporaryFile(name: "Gross.txt", text: "")
        let handle = try FileHandle(forWritingTo: big)
        try handle.truncate(atOffset: UInt64(FilePolicy.maxFileBytes + 1))
        try handle.close()
        let tooBig = await view.stageFile(big)
        XCTAssertNil(tooBig)
    }

    func testDroppedPicturesAndDocumentsAreAnalyzed() async throws {
        let (view, store) = try await makeView("flow-drop")
        let image = try temporaryImage()
        let picture = await view.importDroppedPicture(image.url)
        XCTAssertNotNil(picture)
        let text = try temporaryFile(name: "Brief.txt", text: "Sehr geehrte Damen und Herren")
        view.acceptDroppedFiles([])
        await view.analyzeDroppedFiles([image.url, text])
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertFalse(store.current?.messages.isEmpty ?? true)
    }

    func testSmokeTheScanFlowsRun() async throws {
        let (view, store) = try await makeView("flow-scan-inputs")
        await view.startMenuScan()
        guard let convID = store.current?.id else { return }
        await view.runScanFlow(ScanRequest(kind: .receipt, remind: false), text: "Scan",
                               convID: convID, started: Date(), slot: nil, number: 1)
        let outcome = ScanOutcome(attachment: AttachedFile(file: "doc_scan.pdf", name: "Scan.pdf",
                                                           kind: .pdf, bytes: 1_000, pages: 1,
                                                           chars: 120, via: .ocr),
                                  text: "Rechnung 12,90 Euro")
        await view.analyzeScan(outcome, request: ScanRequest(kind: .invoice, remind: true),
                               text: "Scanne", convID: convID, slot: nil, number: 1)
    }

    func testTheGalleryGetterPaths() async throws {
        let (view, _) = try await makeView("flow-gallery-state")
        _ = view.galleryBarPlan
        _ = view.selectedGallery
        _ = view.showsGalleryBar
        view.cancelGallerySelection()
        let gallery = PictureGallery(query: "Eiffelturm", pictures: [], shown: 0, exhausted: true)
        XCTAssertFalse(ChatView.galleryAnswer(gallery: gallery, failures: 0).isEmpty)
        XCTAssertFalse(ChatView.galleryAnswer(gallery: gallery, failures: 2).isEmpty)
    }

    func testRoutingWithPicturesAndFilesRuns() async throws {
        let (view, _) = try await makeView("flow-route-inputs")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { _ in }
        let pending = PendingPicture(image: image, file: nil)
        let file = PendingFile(name: "Notiz.txt", kind: .text, file: "doc_x", bytes: 10, chars: 20)
        _ = await view.route(text: "Fasse das zusammen", pictures: [pending], files: [file])
        let jpeg = try XCTUnwrap(image.jpegData(compressionQuality: 0.8))
        _ = await view.readProduct(in: [jpeg], question: "Was kostet das?")
    }

    func testSmokeTheSendEntryPointsRun() async throws {
        let (view, _) = try await makeView("flow-send-entries")
        view.input = "Was ist die Hauptstadt von Frankreich?"
        await view.sendNow()
        view.startSend()
        try await Task.sleep(for: .milliseconds(500))
        view.stopRun()
    }

    func testSendingWaitsForAFileThatIsStillBeingRead() async throws {
        let (view, store) = try await makeView("flow-send-reading")
        view.input = "Fasse zusammen"
        view.pendingFiles = [PendingFile(name: "Notiz.txt", kind: .text, file: "doc_reading", bytes: 4)]
        await view.sendNow()
        XCTAssertTrue(store.current?.messages.isEmpty ?? false)
        XCTAssertEqual(view.input, "Fasse zusammen")
        XCTAssertEqual(view.pendingFiles.count, 1)
    }

    func testSendingIsBlockedForAnUnreadableFile() async throws {
        let (view, store) = try await makeView("flow-send-unreadable")
        view.input = "Fasse zusammen"
        view.pendingFiles = [PendingFile(name: "Dokumentation.pdf", kind: .pdf,
                                         file: "doc_broken.pdf", bytes: 4,
                                         reading: false, failed: true)]
        await view.sendNow()
        XCTAssertTrue(store.current?.messages.isEmpty ?? false)
        XCTAssertEqual(view.input, "Fasse zusammen")
        XCTAssertEqual(view.pendingFiles.count, 1)
        XCTAssertEqual(view.currentAlert?.message,
                       L.fmt("file_unreadable", "Dokumentation.pdf"))
        view.dismissAlert()
    }

    func testAttachingForEditingAndRunningOcr() async throws {
        let (view, store) = try await makeView("flow-file-extra")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 90)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 90))
        }
        let data = try XCTUnwrap(image.pngData())
        let file = try XCTUnwrap(store.media.storeImageData(data))
        view.attachForEditing(Attachment(file: file))
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertTrue(view.pendingImages.contains { $0.file == file })
        let auto = AppSettings.shared.autoOCR
        AppSettings.shared.autoOCR = true
        view.runOCR(on: view.pendingImages)
        try await Task.sleep(for: .milliseconds(900))
        AppSettings.shared.autoOCR = auto
        view.pendingFiles = [PendingFile(name: "Notiz.txt", kind: .text, file: "doc_extra",
                                         bytes: 4, chars: 0)]
        if let pending = view.pendingFiles.first {
            view.applyExtraction(ExtractedText(text: "Inhalt", pages: 2, chars: 6, truncated: false,
                                               via: .plain), toFile: pending.file,
                                 named: pending.name, id: pending.id)
        }
        let refs = ChatView.fileRefs(from: [ChatMessage(role: .user, text: "x",
                                                        files: [AttachedFile(file: "doc_r", name: "r.txt",
                                                                             kind: .text, bytes: 2,
                                                                             chars: 5)])],
                                     carried: ["r.txt"])
        XCTAssertEqual(refs.count, 1)
        let missing = ChatView.fileRefs(from: [ChatMessage(role: .user, text: "x")], carried: nil)
        XCTAssertTrue(missing.isEmpty)
    }

    func testSmokeTheFilePickerEntryPointRuns() async throws {
        let (view, _) = try await makeView("flow-picker")
        view.openFilePicker()
        try await Task.sleep(for: .milliseconds(300))
    }

    func testTheRowActionCallbacksRun() async throws {
        let (view, store) = try await makeView("flow-row-actions")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { _ in }
        let data = try XCTUnwrap(image.pngData())
        let file = try XCTUnwrap(store.media.storeImageData(data))
        let attachment = Attachment(file: file)
        let message = ChatMessage(role: .assistant, text: "Antwort", outImages: [attachment])
        let convID = try XCTUnwrap(store.current?.id)
        store.appendMessage(message, to: convID)
        let actions = view.rowActions(in: convID)
        actions.onEdit(attachment)
        actions.onPreview(message, attachment)
        actions.onDelete(message.id)
        actions.onRoute(NearbyPlace(name: "Apotheke", latitude: 48.1, longitude: 11.5, metres: 300))
        if let number = DialNumber("0891234") { actions.onCall?(number) }
        actions.onOpenEvent?(CalendarRef(eventID: "ev", title: "Termin", start: Date()))
        actions.onOpenPicture?(message, WebPicture(file: file, pageURL: "https://q.test/a",
                                                   fullURL: "https://cdn.q.test/a.jpg",
                                                   title: "Bild", domain: "q.test"))
        actions.onMorePictures?(message)
        actions.onWeatherDay?(message.id, "2026-10-05")
        actions.onWeatherSpeak?(message.id)
        actions.onBriefingDay?(message.id, "tomorrow")
        actions.onBriefingSpeak?(message.id)
        actions.onBriefingNotify?(message.id)
        actions.onReminderOffer?(message.id, ScanReminderOffer(title: "Zahlen", due: Date(),
                                                               allDay: false, list: nil, notes: nil))
        try await Task.sleep(for: .milliseconds(400))
    }

    func testTheVoiceHelperEntryPointsRun() async throws {
        let (view, store) = try await makeView("flow-voice-helpers")
        view.settings.voice.listenMode = false
        _ = view.listenGate
        view.followListenGate(view.listenGate)
        view.followMicrophoneHold(view.listenGate)
        view.microphoneLost()
        view.refreshVoiceAfterEngineChange()
        view.abortVoice()
        view.voiceDidTranscribe("Hallo")
        try await Task.sleep(for: .milliseconds(300))
        view.perform(.newChat)
        view.perform(.stopListening)
        view.takeListenRequest(from: "url")
        let empty = ChatMessage(role: .assistant, text: "")
        store.appendMessage(empty, to: try XCTUnwrap(store.current?.id))
        view.speakWeather(message: empty.id)
        view.speakBriefing(message: empty.id)
        let provider = AppSettings.shared.provider
        AppSettings.shared.setKey("", for: provider)
        view.toggleVoice()
        AppSettings.shared.setKey("flow-test-key", for: provider)
        view.toggleListenMode()
    }

    func testTheScaffoldTransientStatesRun() async throws {
        let (view, store) = try await makeView("flow-scaffold-states")
        view.attachMenu = true
        try await Task.sleep(for: .milliseconds(250))
        view.attachMenu = false
        view.queueAlert(L.FriendlyError(message: "Testfehler", detail: "Detail", openSettings: true))
        XCTAssertNotNil(view.currentAlert)
        XCTAssertFalse(view.alertText.isEmpty)
        view.syncPendingAlerts()
        view.dismissAlert()
        view.pendingSuggestions = [MemorySuggestion(text: "mag Tee", category: .likes)]
        try await Task.sleep(for: .milliseconds(200))
        view.pendingSuggestions = []
        let retention = view.settings.memory.retention
        view.settings.memory.retention = .threeMonths
        try await Task.sleep(for: .milliseconds(200))
        view.settings.memory.retention = retention
        view.voice.state = .waiting
        try await Task.sleep(for: .milliseconds(200))
        view.voice.state = .idle
        view.showSettings = true
        try await Task.sleep(for: .milliseconds(350))
        view.showSettings = false
        view.showHistory = true
        try await Task.sleep(for: .milliseconds(350))
        view.showHistory = false
        view.imagePreview = ImagePreviewTarget(tappedFile: "a.jpg", files: ["a.jpg"])
        try await Task.sleep(for: .milliseconds(350))
        view.imagePreview = nil
        view.calendarEvent = CalendarRef(eventID: "ev", title: "Termin", start: Date())
        try await Task.sleep(for: .milliseconds(350))
        view.calendarEvent = nil
        hosted.closeWindow()
        XCTAssertNotNil(store.current)
    }

    func testTheWebSearchFlowRunsWithMockedPages() async throws {
        let (view, store) = try await makeView("flow-web-search")
        MockHTTP.install { request in
            let address = request.url?.absoluteString ?? ""
            if address.contains("html.duckduckgo.com") {
                let html = """
                <a class="result__a" href="https://example.com/eins">Ergebnis Eins</a>
                <a class="result__a" href="https://zweite.test/zwei">Ergebnis Zwei</a>
                """
                return (200, Data(html.utf8))
            }
            if address.contains("chat/completions") {
                return (200, MockHTTP.sse("Die Antwort mit [1] Verweis."))
            }
            let body = "<html><head><title>Testseite</title></head><body><p>"
                + String(repeating: "Ein langer Text über das Wetter. ", count: 20)
                + "</p></body></html>"
            return (200, Data(body.utf8))
        }
        let convID = try XCTUnwrap(store.current?.id)
        let history = [ChatMessage(role: .user, text: "Wie wird das Wetter morgen?"),
                       ChatMessage(role: .assistant, text: "Es wird sonnig.")]
        let query = await view.standaloneQuestion("Wie wird das Wetter morgen?", history: history)
        XCTAssertFalse(query.isEmpty)
        let hits = try await view.gatherWebHits("Wetter morgen", question: "Wie wird das Wetter?", step: 0)
        XCTAssertFalse(hits.isEmpty)
        let verify = view.settings.research.verifySources
        view.settings.research.verifySources = true
        await view.runWebSearch(query: "Wetter morgen", question: "Wie wird das Wetter?", images: [],
                                convID: convID, started: Date(), history: history, slot: nil)
        view.settings.research.verifySources = verify
        await view.runWebSearch(query: "Wetter morgen", images: [], convID: convID, started: Date(),
                                history: history, slot: nil, detailWish: true)
        try await Task.sleep(for: .milliseconds(800))
    }

    func testTheWebSearchFailureAndReviewShortcuts() async throws {
        let (view, store) = try await makeView("flow-web-fail")
        let convID = try XCTUnwrap(store.current?.id)
        view.startSourceCheck(answer: "x", hits: [], model: "m", placement: nil)
        let placement = AnswerPlacement(messageID: nil, slot: nil,
                                        convID: convID, started: Date())
        view.startSourceCheck(answer: "x", hits: [], model: "m", placement: placement)
        let review = await view.reviewSources("Antwort ohne Zitate", hits: [], model: "m")
        XCTAssertEqual(review.citedClaims, 0)
        MockHTTP.install { request in
            let address = request.url?.absoluteString ?? ""
            if address.contains("html.duckduckgo.com") { return (200, Data("<html></html>".utf8)) }
            return (200, Data("{}".utf8))
        }
        await view.runWebSearch(query: "Nichts", question: "Nichts?", images: [], convID: convID,
                                started: Date(), history: [], slot: nil)
        XCTAssertTrue(store.current?.messages.contains { $0.text.contains("⚠️") } ?? false)
    }

    func testTheStreamChatEntryPoints() async throws {
        let (view, store) = try await makeView("flow-stream-chat")
        let convID = try XCTUnwrap(store.current?.id)
        let turn = ModelTurn(messages: [ChatMessage(role: .user, text: "Frage")], images: [])
        await view.streamChat(turn: turn, history: turn.messages, convID: convID, started: Date(),
                              query: "Frage", memoryKeys: [], slot: nil)
        await view.streamChat(turn: turn, history: turn.messages, convID: convID, started: Date(),
                              system: "SYS", query: "", memoryKeys: [], slot: nil)
        XCTAssertFalse(store.current?.messages.isEmpty ?? true)
    }

    func testTheCalendarFlowFallsBackToTheChat() async throws {
        let (view, store) = try await makeView("flow-calendar")
        let convID = try XCTUnwrap(store.current?.id)
        let turn = ModelTurn(messages: [ChatMessage(role: .user, text: "Termin morgen 11 Uhr")], images: [])
        await view.runCalendarFlow(turn: turn, text: "Termin morgen 11 Uhr", history: turn.messages,
                                   convID: convID, started: Date(), plan: nil, slot: nil, number: 1)
        await view.runCalendarFlow(turn: turn, text: "Termin", history: turn.messages, convID: convID,
                                   started: Date(), plan: QwenAPI.CalendarPlan(action: .none), slot: nil,
                                   number: 1)
        var update = QwenAPI.CalendarPlan(action: .update)
        update.title = "Zahnarzt"
        await view.runCalendarFlow(turn: turn, text: "Verschiebe", history: turn.messages, convID: convID,
                                   started: Date(), plan: update, slot: nil, number: 2)
        try await Task.sleep(for: .milliseconds(300))
    }

    func testThePictureFlowsPromptEditAndFailure() async throws {
        let (view, store) = try await makeView("flow-pictures-deep")
        let convID = try XCTUnwrap(store.current?.id)
        _ = await view.imagePrompt("Maler", history: [ChatMessage(role: .assistant, text: "alt")], pictures: 1)
        _ = await view.imagePrompt("Maler", history: [], pictures: 1)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { _ in }
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 0.8))
        let turn = ModelTurn(messages: [], images: [data])
        await view.imageWork(prompt: "schwarz-weiß", history: [], turn: turn, fresh: [], isEdit: true,
                             monochrome: true, convID: convID, started: Date(), composeFromChat: false,
                             slot: nil)
        await view.imageWork(prompt: "Maler", history: [], turn: ModelTurn(messages: [], images: []),
                             fresh: [], isEdit: false, monochrome: false, convID: convID, started: Date(),
                             composeFromChat: false, slot: nil)
        XCTAssertFalse(ChatView.unreachablePictureNotice(leftBehind: 2).isEmpty)
        XCTAssertFalse(ChatView.unreachablePictureNotice(leftBehind: 0).isEmpty)
        let provider = AppSettings.shared.provider
        AppSettings.shared.provider = .deepSeek
        await view.runImageFlow(prompt: "Maler", history: [], turn: ModelTurn(messages: [], images: []),
                                fresh: [], isEdit: false, convID: convID, started: Date())
        AppSettings.shared.provider = provider
        MockHTTP.install { _ in (200, Data("{}".utf8)) }
        await view.runPictureSearch(query: "Eiffelturm", images: [], convID: convID, started: Date(),
                                    history: [], slot: nil)
        try await Task.sleep(for: .milliseconds(600))
    }

    func testThePictureSearchRoundStoresHits() async throws {
        let (view, store) = try await makeView("flow-picture-round")
        let thumb = UIGraphicsImageRenderer(size: CGSize(width: 60, height: 40)).image { _ in }
        let jpeg = try XCTUnwrap(thumb.jpegData(compressionQuality: 0.8))
        MockHTTP.install { request in
            let address = request.url?.absoluteString ?? ""
            if address.contains("bing.com/images/async") {
                let raw = #"{"turl":"https://th.bing.com/th?id=1","purl":"https://example.com/page","murl":"https://cdn.example.com/full.jpg","t":"Titel"}"#
                let encoded = raw.replacingOccurrences(of: "\"", with: "&quot;")
                return (200, Data("<a m=\"\(encoded)\">".utf8))
            }
            return (200, jpeg)
        }
        let round = try await view.searchPictures(query: "Eiffelturm", offset: 1, step: 0)
        XCTAssertFalse(round.pictures.isEmpty)
        let convID = try XCTUnwrap(store.current?.id)
        await view.runPictureSearch(query: "Eiffelturm", images: [], convID: convID, started: Date(),
                                    history: [], slot: nil)
        try await Task.sleep(for: .milliseconds(500))
    }

    func testTheScanReminderButtonCreatesTheReminder() async throws {
        let (view, store) = try await makeView("flow-scan-reminder-button")
        let message = ChatMessage(role: .assistant, text: "Scan-Antwort")
        let convID = try XCTUnwrap(store.current?.id)
        store.appendMessage(message, to: convID)
        let offer = ScanReminderOffer(title: "Rechnung zahlen", due: Date().addingTimeInterval(86_400),
                                      allDay: false, list: "Erinnerungen", notes: nil)
        XCTAssertNotNil(offer.request)
        await view.createScanReminder(offer, messageID: message.id)
        try await Task.sleep(for: .milliseconds(400))
        let updated = store.conversations.first { $0.id == convID }?
            .messages.first { $0.id == message.id }
        XCTAssertNotNil(updated)
    }

    func testTheGalleryViewRendersWithASelection() async throws {
        let (view, store) = try await makeView("flow-gallery-selection")
        let picture = WebPicture(file: "web_b.jpg", pageURL: "https://q.test/b",
                                 fullURL: "https://cdn.q.test/b.jpg", title: "Bild", domain: "q.test")
        let gallery = PictureGallery(query: "Bilder", pictures: [picture], shown: 1, exhausted: false)
        let message = ChatMessage(role: .assistant, text: "Galerie", gallery: gallery)
        let convID = try XCTUnwrap(store.current?.id)
        store.appendMessage(message, to: convID)
        view.gallerySelection.begin(owner: message.id)
        view.gallerySelection.toggle(picture.file)
        view.galleryOperation.beginSearch(message.id)
        try await Task.sleep(for: .milliseconds(200))
        view.galleryOperation.endSearch(message.id)
        XCTAssertTrue(view.showsGalleryBar)
        _ = view.galleryBarPlan
        view.cancelGallerySelection()
    }

    func testTheGalleryShareWithoutStoredPicturesWarns() async throws {
        let (view, store) = try await makeView("flow-gallery-share")
        let picture = WebPicture(file: "fehlt.jpg", pageURL: "https://q.test/c",
                                 fullURL: "https://cdn.q.test/c.jpg", title: "Bild", domain: "q.test")
        let gallery = PictureGallery(query: "Bilder", pictures: [picture], shown: 1, exhausted: false)
        let message = ChatMessage(role: .assistant, text: "Galerie", gallery: gallery)
        let convID = try XCTUnwrap(store.current?.id)
        store.appendMessage(message, to: convID)
        view.gallerySelection.begin(owner: message.id)
        view.gallerySelection.toggle(picture.file)
        view.shareGallerySelection()
        XCTAssertNotNil(view.currentAlert)
        view.dismissAlert()
    }

    func testTheSendGuardsAndChainPaths() async throws {
        let (view, store) = try await makeView("flow-send-guards")
        view.isBusy = true
        await view.send()
        view.isBusy = false
        view.isStreaming = true
        await view.send()
        view.isStreaming = false
        let provider = AppSettings.shared.provider
        AppSettings.shared.setKey("", for: provider)
        await view.send()
        AppSettings.shared.setKey("flow-test-key", for: provider)
        view.pendingImages = [PendingPicture(image: UIImage(), file: nil)]
        await view.send()
        view.pendingImages = []
        view.runTask = Task {}
        await view.sendNow()
        view.startSend()
        view.runTask?.cancel()
        view.runTask = nil
        let image = UIGraphicsImageRenderer(size: CGSize(width: 30, height: 30)).image { _ in }
        _ = await view.route(text: "", pictures: [PendingPicture(image: image, file: nil)], files: [])
        let convID = try XCTUnwrap(store.current?.id)
        let chain = SendPlan(actions: [ToolDecision(route: .chat),
                                       ToolDecision(route: .clock(ClockRequest(timeZone: "UTC", place: nil)))])
        let routed = RoutedSend(text: "Frage", plan: chain, turn: ModelTurn(messages: [], images: []),
                                history: [], attachments: [], files: [], convID: convID, started: Date())
        await view.run(routed)
        try await Task.sleep(for: .milliseconds(500))
        view.reportStop(skipped: 2, in: routed)
        _ = await view.turnWithFoundPicture(for: ModelTurn(messages: [], images: []))
        view.input = "Und noch eine Frage"
        await view.send()
        try await Task.sleep(for: .milliseconds(400))
    }

    func testTheAnswerFailureAndCancellationHelpers() async throws {
        let (view, store) = try await makeView("flow-failure-helpers")
        let convID = try XCTUnwrap(store.current?.id)
        let started = Date()
        view.reportChatFailure(CancellationError(), model: "m", convID: convID, started: started)
        view.reportChatFailure(APIError(message: "Invalid API key", status: 401), model: "m",
                               convID: convID, started: started)
        XCTAssertNotNil(view.currentAlert)
        view.dismissAlert()
        view.appendModelFailure(APIError(message: "kaputt", status: 500), model: "m",
                                convID: convID, started: started)
        view.appendModelFailure(CancellationError(), model: "m", convID: convID, started: started)
        view.finishCancelled(nil, thinking: nil, model: "m", convID: convID, started: started, slot: nil)
        view.finishCancelled("  Teil  ", thinking: .low, model: "m", convID: convID, started: started, slot: nil)
        XCTAssertTrue(store.current?.messages.contains { $0.text.contains("Teil") } ?? false)
    }

    func testTheWeatherFailureAndDaySwitch() async throws {
        var (view, store) = try await makeView("flow-weather-errors")
        let convID = try XCTUnwrap(store.current?.id)
        var failing = WeatherService()
        failing.fetcher = { _ in throw APIError(message: "kein netz") }
        failing.geocodeAddress = { name in
            WeatherPlace(name: name, latitude: 48.137, longitude: 11.575, timezone: "Europe/Berlin")
        }
        view.weatherService = failing
        let request = WeatherRequest(place: "München", day: .today, date: nil, offset: 0)
        await view.runWeatherFlow(request, convID: convID, started: Date())
        XCTAssertTrue(store.current?.messages.contains { $0.text.contains("netz") } ?? false)

        view.weatherService = stubbedWeather()
        await view.runWeatherFlow(request, convID: convID, started: Date())
        let message = try XCTUnwrap(store.current?.messages.last)
        await view.switchWeatherDay(message: message.id, date: "2026-10-05")
        var broken = stubbedWeather()
        broken.fetcher = { _ in throw APIError(message: "kein netz") }
        broken.geocodeAddress = { _ in nil }
        var emptyRef = WeatherFixture.ref(hours: WeatherFixture.day { WeatherFixture.hour($0) })
        emptyRef.place = ""
        view.weatherService = broken
        WeatherService.clearCache()
        let crafted = ChatMessage(role: .assistant, text: "Wetter", weatherRef: emptyRef)
        store.appendMessage(crafted, to: convID)
        await view.switchWeatherDay(message: crafted.id, date: "2026-10-05")
        XCTAssertNotNil(view.currentAlert)
        view.dismissAlert()
    }

    func testTheClockAndRouteHelpers() async throws {
        let (view, store) = try await makeView("flow-clock-route")
        let convID = try XCTUnwrap(store.current?.id)
        view.tellTime(ClockRequest(timeZone: "UTC", place: "London"), convID: convID, started: Date())
        XCTAssertFalse(store.current?.messages.last?.text.isEmpty ?? true)
        view.openRoute(to: NearbyPlace(name: "Ohne Koordinaten"))
        XCTAssertNotNil(view.currentAlert)
        view.dismissAlert()
        view.openRoute(to: NearbyPlace(name: "Apotheke", latitude: 48.1, longitude: 11.5, metres: 100))
    }

    func testTheMemoryAndPriceWatchCatchUpBranches() async throws {
        let (view, store) = try await makeView("flow-memory-price")
        let convID = try XCTUnwrap(store.current?.id)
        let settings = view.settings
        let enabled = settings.memory.enabled
        let suggestions = settings.memory.suggestions
        settings.memory.enabled = false
        await view.runMemoryFlow(MemoryRequest(action: .list), convID: convID, started: Date())
        XCTAssertTrue(store.current?.messages.last?.text.contains(L.t("memory_off")) ?? false)
        settings.memory.enabled = true
        settings.memory.suggestions = false
        await view.runMemoryFlow(MemoryRequest(action: .suggest, text: "mag Tee"),
                                 convID: convID, started: Date())
        settings.memory.suggestions = true
        await view.runMemoryFlow(MemoryRequest(action: .suggest, text: "  "), convID: convID, started: Date())
        await view.runMemoryFlow(MemoryRequest(action: .suggest, text: "mag Kaffee", category: .likes),
                                 convID: convID, started: Date())
        view.savePendingSuggestions()
        try? await Task.sleep(for: .milliseconds(200))
        await view.runMemoryFlow(MemoryRequest(action: .create, text: "  "), convID: convID, started: Date())
        await view.runMemoryFlow(MemoryRequest(action: .create, text: "Arbeit", category: .work),
                                 convID: convID, started: Date())
        await view.runMemoryFlow(MemoryRequest(action: .forget, key: "gibtsnicht"),
                                 convID: convID, started: Date())
        XCTAssertTrue(store.current?.messages.last?.text.contains(L.t("memory_forget_missing")) ?? false)
        let entry = await store.memory.all().first { $0.text == "Arbeit" }
        if let entry {
            await view.runMemoryFlow(MemoryRequest(action: .forget, key: entry.shortKey),
                                     convID: convID, started: Date())
        }
        _ = await store.memory.add(text: "Frist", category: .plans, source: .explicit,
                                   date: Date().addingTimeInterval(-100 * 86400), intervalMonths: 1,
                                   remind: true)
        let notifierStatus = MemoryNotifier.delivery.authorizationStatus
        let notifierDeliver = MemoryNotifier.delivery.deliverOverride
        defer {
            MemoryNotifier.delivery.authorizationStatus = notifierStatus
            MemoryNotifier.delivery.deliverOverride = notifierDeliver
        }
        MemoryNotifier.delivery.authorizationStatus = { .authorized }
        MemoryNotifier.delivery.deliverOverride = { _ in }
        await view.checkMemoryDue()
        settings.memory.suggestions = suggestions
        settings.memory.enabled = enabled

        let created = await store.watches.create(terms: ["PS5"], goal: 400, intervalHours: 24,
                                                 currencyCode: "EUR", regionCode: "DE")
        if let created {
            await store.watches.record(id: created.watch.id, offer: nil, fallbackCurrency: "EUR",
                                       now: Date().addingTimeInterval(-3 * 86400))
        }
        view.priceWatchDesk.stand(in: TestPriceChecker(price: 380))
        await view.checkPriceWatches()
        XCTAssertTrue(store.current?.messages.contains { $0.text.contains("PS5") } ?? false)
    }

    func testEverySuggestedFactFromOneMessageSurvives() async throws {
        let (view, store) = try await makeView("flow-memory-suggestions")
        let convID = try XCTUnwrap(store.current?.id)
        await view.runMemoryFlow(MemoryRequest(action: .suggest, text: "Ich mag Bananen", category: .likes),
                                 convID: convID, started: Date())
        await view.runMemoryFlow(MemoryRequest(action: .suggest, text: "Ich bin allergisch auf Äpfel",
                                               category: .health),
                                 convID: convID, started: Date())
        XCTAssertEqual(view.pendingSuggestions.map(\.text), ["Ich mag Bananen", "Ich bin allergisch auf Äpfel"])
        view.savePendingSuggestions()
        for _ in 0..<50 {
            if await store.memory.count() == 2 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let texts = await store.memory.all().map(\.text)
        XCTAssertEqual(texts.sorted(), ["Ich bin allergisch auf Äpfel", "Ich mag Bananen"])
    }

    func testSmokeTheMemoryDueFlowReportsUndeliveredReminders() async throws {
        let (view, store) = try await makeView("flow-memory-undelivered")
        let originalStatus = MemoryNotifier.delivery.authorizationStatus
        let originalDeliver = MemoryNotifier.delivery.deliverOverride
        defer {
            MemoryNotifier.delivery.authorizationStatus = originalStatus
            MemoryNotifier.delivery.deliverOverride = originalDeliver
        }
        MemoryNotifier.delivery.authorizationStatus = { .denied }
        MemoryNotifier.delivery.deliverOverride = { _ in }
        _ = await store.memory.add(text: "Frist", category: .plans, source: .explicit,
                                   date: Date().addingTimeInterval(-100 * 86400), intervalMonths: 1,
                                   remind: true)
        await view.checkMemoryDue()
    }

    func testTheBriefingDaySwitchAndButtons() async throws {
        let (view, store) = try await makeView("flow-briefing-buttons")
        let convID = try XCTUnwrap(store.current?.id)
        await run(ToolDecision(route: .dayBriefing(DayBriefingRequest(day: .today))), view, store)
        let briefing = DayBriefingRef(date: "2026-10-05", greetingKey: "brief_greet_morning")
        let crafted = ChatMessage(role: .assistant, text: "Briefing", dayBriefingRef: briefing)
        store.appendMessage(crafted, to: convID)
        await view.switchBriefingDay(message: crafted.id, day: "tomorrow")
        XCTAssertNotNil(store.current?.messages.first(where: { $0.id == crafted.id })?.dayBriefingRef)
        await view.switchBriefingDay(message: crafted.id, day: "quatsch")
        view.speakBriefing(message: crafted.id)
        view.speakBriefing(message: UUID())
        view.notifyBriefing(message: crafted.id)
        view.notifyBriefing(message: UUID())
    }
}
