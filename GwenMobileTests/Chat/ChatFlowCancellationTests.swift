@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit
@testable import GwenMobileProbes

private actor CancellationGate {
    private var started = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func markStarted() {
        started = true
        let pending = waiters
        waiters = []
        for waiter in pending { waiter.resume() }
    }

    func wait() async {
        if started { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func waitUntilCancelled() async {
        markStarted()
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}

@MainActor
private final class GateDialer: CallPlacing {
    let gate: CancellationGate
    var way: String { "gate" }

    init(gate: CancellationGate) {
        self.gate = gate
    }

    func place(_ number: DialNumber) async -> CallStart {
        await gate.waitUntilCancelled()
        return .failed
    }
}

@MainActor
private final class GateMessenger: MessageSending {
    let gate: CancellationGate
    var way: String { "gate" }

    init(gate: CancellationGate) {
        self.gate = gate
    }

    func send(_ text: String, to number: DialNumber) async -> MessageSendResult {
        await gate.waitUntilCancelled()
        return .cancelled
    }
}

@MainActor
private final class GateTimer: TimerSetting {
    let gate: CancellationGate

    init(gate: CancellationGate) {
        self.gate = gate
    }

    func set(_ request: TimerRequest) async -> TimerSettingResult {
        await gate.waitUntilCancelled()
        return .failed("abgebrochen")
    }
}

@MainActor
private final class GateReminderStore: ReminderStoring {
    let gate: CancellationGate

    init(gate: CancellationGate) {
        self.gate = gate
    }

    func hasAccess() async -> Bool { true }
    func lists() async -> [String] { ["Privat"] }
    func defaultListTitle() async -> String? { "Privat" }

    func open() async throws -> [StoredReminder] {
        await gate.waitUntilCancelled()
        throw CancellationError()
    }

    func create(_ draft: ReminderDraft) async throws -> StoredReminder {
        throw CancellationError()
    }

    func update(_ id: String, with draft: ReminderDraft) async throws -> StoredReminder {
        throw CancellationError()
    }

    func complete(_ id: String, at date: Date) async throws -> StoredReminder {
        throw CancellationError()
    }

    func delete(_ id: String) async throws {
        throw CancellationError()
    }
}

@MainActor
private final class FinishingDialer: CallPlacing {
    let gate: CancellationGate
    var way: String { "fertig" }

    init(gate: CancellationGate) {
        self.gate = gate
    }

    func place(_ number: DialNumber) async -> CallStart {
        await gate.waitUntilCancelled()
        return .dialing
    }
}

@MainActor
private final class FinishingMessenger: MessageSending {
    let gate: CancellationGate
    var way: String { "fertig" }

    init(gate: CancellationGate) {
        self.gate = gate
    }

    func send(_ text: String, to number: DialNumber) async -> MessageSendResult {
        await gate.waitUntilCancelled()
        return .sent(direct: true)
    }
}

@MainActor
private final class FinishingTimer: TimerSetting {
    let gate: CancellationGate

    init(gate: CancellationGate) {
        self.gate = gate
    }

    func set(_ request: TimerRequest) async -> TimerSettingResult {
        await gate.waitUntilCancelled()
        return .set(duration: request.duration, way: "fertig")
    }
}

@MainActor
private final class FinishingReminderStore: ReminderStoring {
    let gate: CancellationGate

    init(gate: CancellationGate) {
        self.gate = gate
    }

    func hasAccess() async -> Bool { true }
    func lists() async -> [String] { ["Privat"] }
    func defaultListTitle() async -> String? { "Privat" }
    func open() async throws -> [StoredReminder] { [] }

    func create(_ draft: ReminderDraft) async throws -> StoredReminder {
        await gate.waitUntilCancelled()
        return StoredReminder(id: "rem-1", title: draft.title ?? "", list: draft.list ?? "Privat")
    }

    func update(_ id: String, with draft: ReminderDraft) async throws -> StoredReminder {
        throw CancellationError()
    }

    func complete(_ id: String, at date: Date) async throws -> StoredReminder {
        throw CancellationError()
    }

    func delete(_ id: String) async throws {
        throw CancellationError()
    }
}

@MainActor
private struct EmptyBriefingCalendar: BriefingCalendarReading {
    func briefingEvents(on day: Date) -> [DayBriefingEvent] { [] }
}

@MainActor
private struct EmptyBriefingReminders: BriefingReminderReading {
    func briefingReminders() async -> [StoredReminder] { [] }
}

@MainActor
private struct GateBriefingWeather: BriefingWeatherLoading {
    let gate: CancellationGate

    func briefingWeather(dayOffset: Int) async throws -> WeatherRef {
        await gate.waitUntilCancelled()
        throw CancellationError()
    }
}

@MainActor
final class ChatFlowCancellationTests: GwenTestCase {
    private let hosted = HostedChatView()

    override func setUp() {
        super.setUp()
        MockHTTP.install(MockHTTP.defaultHandler)
    }

    override func tearDown() async throws {
        MockHTTP.uninstall()
        MockHTTPProtocol.dataDelay = 0
        DocumentScanner.shared.isSupportedOverride = nil
        DocumentScanner.shared.scanOverride = nil
        TranslationFlow.runOverride = nil
        hosted.close()
        dismissPresentedSheets()
        try await super.tearDown()
    }

    private func makeView(_ prefix: String) async throws -> (ChatView, ChatStore) {
        let store = HostedChatView.store(temporaryPaths(prefix))
        AppSettings.shared.setKey("cancel-test-key", for: AppSettings.shared.provider)
        let view = try await hosted.open(store, in: self)
        WeatherService.clearCache()
        return (view, store)
    }

    private func messageCount(_ store: ChatStore) -> Int {
        store.current?.messages.count ?? 0
    }

    private func runAlreadyCancelled(_ body: @escaping @MainActor () async -> Void) async {
        let task = Task { @MainActor in
            while !Task.isCancelled { await Task.yield() }
            await body()
        }
        task.cancel()
        await task.value
    }

    func testTheCallAndMessageFlowsStopAfterCancellation() async throws {
        let (view, store) = try await makeView("cancel-desk")
        let convID = try XCTUnwrap(store.current?.id)
        let before = messageCount(store)

        let callGate = CancellationGate()
        view.callDesk.stand(in: GateDialer(gate: callGate), directory: FixtureContacts())
        let call = Task { @MainActor in
            await view.runCallFlow(ContactRequest(person: "Mutter"), convID: convID, started: Date())
        }
        await callGate.wait()
        call.cancel()
        await call.value
        XCTAssertEqual(messageCount(store), before)

        let messageGate = CancellationGate()
        view.messageDesk.stand(in: GateMessenger(gate: messageGate), directory: FixtureContacts())
        let message = Task { @MainActor in
            await view.runMessageFlow(MessageRequest(recipient: ContactRequest(person: "Mutter"),
                                                     text: "Hallo"), convID: convID, started: Date())
        }
        await messageGate.wait()
        message.cancel()
        await message.value
        XCTAssertEqual(messageCount(store), before)
    }

    func testTheReminderAndTimerFlowsStopAfterCancellation() async throws {
        let (view, store) = try await makeView("cancel-reminder")
        let convID = try XCTUnwrap(store.current?.id)
        let before = messageCount(store)

        let reminderGate = CancellationGate()
        let reminderRequest = try XCTUnwrap(ReminderRequest(plan: ReminderPlan(action: .list)))
        view.reminderDesk.stand(in: GateReminderStore(gate: reminderGate), places: ProbePlaceLookup())
        let reminder = Task { @MainActor in
            await view.runReminderFlow(reminderRequest, convID: convID, started: Date())
        }
        await reminderGate.wait()
        reminder.cancel()
        await reminder.value
        XCTAssertEqual(messageCount(store), before)

        let timerGate = CancellationGate()
        view.timerDesk.stand(in: GateTimer(gate: timerGate))
        let timer = Task { @MainActor in
            await view.runTimerFlow(TimerRequest(minutes: 1, seconds: nil, title: "Tee"), convID: convID,
                                    started: Date())
        }
        await timerGate.wait()
        timer.cancel()
        await timer.value
        XCTAssertEqual(messageCount(store), before)
    }

    func testAnActionThatWasCarriedOutStaysInTheChatAfterAStop() async throws {
        let (view, store) = try await makeView("cancel-performed")
        let convID = try XCTUnwrap(store.current?.id)
        let before = messageCount(store)

        let callGate = CancellationGate()
        view.callDesk.stand(in: FinishingDialer(gate: callGate), directory: FixtureContacts())
        let call = Task { @MainActor in
            await view.runCallFlow(ContactRequest(person: "Mutter"), convID: convID, started: Date())
        }
        await callGate.wait()
        call.cancel()
        await call.value
        XCTAssertEqual(messageCount(store), before + 1)

        let messageGate = CancellationGate()
        view.messageDesk.stand(in: FinishingMessenger(gate: messageGate), directory: FixtureContacts())
        let message = Task { @MainActor in
            await view.runMessageFlow(MessageRequest(recipient: ContactRequest(person: "Mutter"),
                                                     text: "Hallo"), convID: convID, started: Date())
        }
        await messageGate.wait()
        message.cancel()
        await message.value
        XCTAssertEqual(messageCount(store), before + 2)

        let reminderGate = CancellationGate()
        let reminderRequest = try XCTUnwrap(ReminderRequest(plan: ReminderPlan(action: .create, title: "Milch")))
        view.reminderDesk.stand(in: FinishingReminderStore(gate: reminderGate), places: ProbePlaceLookup())
        let reminder = Task { @MainActor in
            await view.runReminderFlow(reminderRequest, convID: convID, started: Date())
        }
        await reminderGate.wait()
        reminder.cancel()
        await reminder.value
        XCTAssertEqual(messageCount(store), before + 3)
        XCTAssertEqual(store.current?.messages.last?.reminderRef?.reminderID, "rem-1")

        let timerGate = CancellationGate()
        view.timerDesk.stand(in: FinishingTimer(gate: timerGate))
        let timer = Task { @MainActor in
            await view.runTimerFlow(TimerRequest(minutes: 1, seconds: nil, title: "Tee"), convID: convID,
                                    started: Date())
        }
        await timerGate.wait()
        timer.cancel()
        await timer.value
        XCTAssertEqual(messageCount(store), before + 4)
    }

    func testTheBriefingWeatherAndTranslationFlowsStopAfterCancellation() async throws {
        var (view, store) = try await makeView("cancel-local")
        let convID = try XCTUnwrap(store.current?.id)
        let before = messageCount(store)

        let briefingGate = CancellationGate()
        view.briefingDesk.stand(in: DayBriefingSources(calendar: EmptyBriefingCalendar(),
                                                       reminders: EmptyBriefingReminders(),
                                                       contacts: nil,
                                                       weather: GateBriefingWeather(gate: briefingGate),
                                                       travel: nil))
        let briefing = Task { @MainActor in
            await view.runDayBriefingFlow(DayBriefingRequest(day: .today), convID: convID, started: Date())
        }
        await briefingGate.wait()
        briefing.cancel()
        await briefing.value
        XCTAssertEqual(messageCount(store), before)

        let weatherGate = CancellationGate()
        var weather = WeatherService()
        weather.fetcher = { _ in
            await weatherGate.waitUntilCancelled()
            throw CancellationError()
        }
        weather.geocodeAddress = { name in
            WeatherPlace(name: name, latitude: 52.52, longitude: 13.405, timezone: "Europe/Berlin")
        }
        weather.localSearch = { name in
            WeatherPlace(name: name, latitude: 52.52, longitude: 13.405, timezone: "Europe/Berlin")
        }
        view.weatherService = weather
        WeatherService.clearCache()
        let weatherTask = Task { @MainActor in
            await view.runWeatherFlow(WeatherRequest(place: "Berlin", day: .today, date: nil, offset: 0),
                                      convID: convID, started: Date())
        }
        await weatherGate.wait()
        weatherTask.cancel()
        await weatherTask.value
        XCTAssertEqual(messageCount(store), before)

        let translationGate = CancellationGate()
        TranslationFlow.runOverride = { _, _ in
            await translationGate.waitUntilCancelled()
            throw CancellationError()
        }
        let translation = Task { @MainActor in
            await view.runTranslationFlow(TranslationJob(text: "Guten Morgen", targetCode: "fr"),
                                          convID: convID, started: Date())
        }
        await translationGate.wait()
        translation.cancel()
        await translation.value
        XCTAssertEqual(messageCount(store), before)
    }

    func testTheCalendarAndWebSearchFlowsStopAfterCancellation() async throws {
        let (view, store) = try await makeView("cancel-network")
        let convID = try XCTUnwrap(store.current?.id)
        let before = messageCount(store)

        MockHTTPProtocol.dataDelay = 0.3
        MockHTTP.install { _ in
            (200, Data(#"{"action":"create","title":"Test"}"#.utf8))
        }
        let calendar = Task { @MainActor in
            await view.calendarWork(turn: ModelTurn(messages: [], images: []), text: "Termin",
                                    history: [], convID: convID, started: Date(),
                                    plan: QwenAPI.CalendarPlan(action: .create, title: "Test"), number: 1)
        }
        try await Task.sleep(for: .milliseconds(60))
        calendar.cancel()
        await calendar.value
        XCTAssertEqual(messageCount(store), before)

        MockHTTP.install { _ in (500, Data()) }
        let search = Task { @MainActor in
            await view.runWebSearch(query: "Test", images: [], convID: convID, started: Date(), history: [])
        }
        try await Task.sleep(for: .milliseconds(60))
        search.cancel()
        await search.value
        XCTAssertEqual(messageCount(store), before)
    }

    func testTheScanAndPictureSearchFlowsStopAfterCancellation() async throws {
        let (view, store) = try await makeView("cancel-scan")
        let convID = try XCTUnwrap(store.current?.id)
        store.appendMessage(ChatMessage(role: .user, text: "Scanne das"), to: convID)
        let before = messageCount(store)

        let scanGate = CancellationGate()
        DocumentScanner.shared.isSupportedOverride = true
        DocumentScanner.shared.scanOverride = {
            await scanGate.waitUntilCancelled()
            return nil
        }
        let scan = Task { @MainActor in
            await view.runScanFlow(ScanRequest(kind: .other, remind: false), text: "Scanne das",
                                   convID: convID, started: Date(), slot: nil, number: 1)
        }
        await scanGate.wait()
        scan.cancel()
        await scan.value
        XCTAssertEqual(messageCount(store), before)

        MockHTTPProtocol.dataDelay = 0.3
        MockHTTP.install { _ in (500, Data()) }
        let pictures = Task { @MainActor in
            await view.runPictureSearch(query: "Berge", images: [], convID: convID,
                                        started: Date(), history: [])
        }
        try await Task.sleep(for: .milliseconds(60))
        pictures.cancel()
        await pictures.value
        XCTAssertEqual(messageCount(store), before)
    }

    func testTheMemoryAndGalleryFlowsHonorCancellation() async throws {
        let (view, store) = try await makeView("cancel-gallery")
        let convID = try XCTUnwrap(store.current?.id)
        let beforeMessages = messageCount(store)
        let beforeMemory = await store.memory.count()

        await runAlreadyCancelled {
            await view.runMemoryFlow(MemoryRequest(action: .create, text: "mag Tee"), convID: convID,
                                     started: Date())
        }
        XCTAssertEqual(messageCount(store), beforeMessages)
        let afterMemory = await store.memory.count()
        XCTAssertEqual(afterMemory, beforeMemory)

        let picture = WebPicture(file: "img_cancel_gallery.jpg", pageURL: "https://q.test/p",
                                 fullURL: "https://q.test/p.jpg", title: "Bild", domain: "q.test")
        let gallery = PictureGallery(query: "Berge", pictures: [picture], shown: 1,
                                     nextOffset: 2, exhausted: false)
        let message = ChatMessage(role: .assistant, text: "Galerie", gallery: gallery)
        store.appendMessage(message, to: convID)
        let afterSetup = messageCount(store)

        MockHTTPProtocol.dataDelay = 0.3
        MockHTTP.install { _ in (500, Data()) }
        let more = Task { @MainActor in
            await view.morePictures(message)
        }
        try await Task.sleep(for: .milliseconds(60))
        more.cancel()
        await more.value
        XCTAssertEqual(messageCount(store), afterSetup)
        XCTAssertEqual(store.current?.messages.first { $0.id == message.id }?.gallery?.nextOffset,
                       gallery.nextOffset)
    }
}
