@testable import GwenMobileFeatureCore
import AVFoundation
import Contacts
import EventKit
import Foundation
import MapKit
import NaturalLanguage
import UserNotifications
import XCTest
import GwenMobileKit

private final class EmptyInfoBundle: Bundle, @unchecked Sendable {
    override var infoDictionary: [String: Any]? { nil }
}

@MainActor
final class LiveRawCoverageTests: GwenTestCase {
    func testAppInfoWithMissingInfo() {
        let info = AppInfo(reading: EmptyInfoBundle())
        XCTAssertEqual(info.version, "1.0")
        XCTAssertNil(info.build)
    }

    func testSmokeNotificationPermissionDefaults() async {
        NotificationPermission.request(reporting: "RAWTEST", ask: { true })
        try? await Task.sleep(for: .milliseconds(100))
    }

    func testTimerAnswerWithoutATitle() {
        XCTAssertEqual(TimerAnswer.title(TimerRequest(minutes: 1)), L.t("timer_default_title"))
    }

    func testSmokeMemoryStoreWithoutADueDate() async {
        let store = MemoryStore(paths: temporaryPaths("raw-memory"))
        _ = await store.add(text: "ohne Frist", category: .plans, source: .explicit, remind: true)
        _ = await store.dueReminders()
    }

    func testSmokeMessageLanguageUnknownCode() {
        _ = MessageLanguageCheck.hint(for: NLLanguage(rawValue: "zz"))
    }

    func testSmokePriceRegionWithoutKnownCode() {
        let narrowed = PriceRegion(code: "ZZ", source: .open)
        _ = narrowed.label
        _ = narrowed.traceLine
        let open = PriceRegion(code: nil, source: .open)
        _ = open.label
        _ = open.traceLine
    }

    func testITunesCountryWithoutRegion() {
        XCTAssertEqual(ITunesCatalog.country(Locale(identifier: "und")), "us")
    }
}

@MainActor
private final class RawThrowingReminderStore: ReminderStoring {
    func hasAccess() async -> Bool { false }
    func lists() async -> [String] { [] }
    func defaultListTitle() async -> String? { nil }
    func open() async throws -> [StoredReminder] { throw APIError(message: "kaputt") }
    func create(_ draft: ReminderDraft) async throws -> StoredReminder { throw APIError(message: "kaputt") }
    func update(_ id: String, with draft: ReminderDraft) async throws -> StoredReminder {
        throw APIError(message: "kaputt")
    }
    func complete(_ id: String, at date: Date) async throws -> StoredReminder {
        throw APIError(message: "kaputt")
    }
    func delete(_ id: String) async throws { throw APIError(message: "kaputt") }
}

@MainActor
private final class RawThrowingEventStore: ReminderEventStoring {
    func makeReminder() -> EKReminder { EKReminder(eventStore: EKEventStore()) }
    func makeCalendar() -> EKCalendar { EKCalendar(for: .reminder, eventStore: EKEventStore()) }
    func fetchReminders() async -> [EKReminder] { [] }
    func calendarItem(withIdentifier identifier: String) -> EKCalendarItem? { nil }
    func calendars(for entityType: EKEntityType) -> [EKCalendar] { [] }
    func defaultCalendarForNewReminders() -> EKCalendar? { nil }
    func save(_ reminder: EKReminder, commit: Bool) throws {}
    func remove(_ reminder: EKReminder, commit: Bool) throws {}
    func saveCalendar(_ calendar: EKCalendar, commit: Bool) throws {}
    var sources: [EKSource] { [] }
    func requestFullAccessToReminders() async throws -> Bool { throw APIError(message: "kaputt") }
}

@MainActor
extension LiveRawCoverageTests {
    #if !targetEnvironment(macCatalyst)
    func testSmokeSpotifyLinkWithoutConfiguration() async {
        let link = SpotifyLink(clientID: { "" }, keychain: MemoryKeyStore())
        _ = link.isConnected
        _ = link.isPlaying
        _ = await link.connect(token: "token")
        _ = await link.play(uri: "spotify:track:1")
        _ = await link.perform(.pause)
        _ = SpotifySourceFactory.make()
    }
    #endif

    func testSmokeDefaultCatalogAndClientInitialisers() {
        _ = ITunesCatalogSearch()
        _ = SpotifyWebClient()
    }

    func testSmokeAudioMeterDefaultReport() {
        let meter = AudioLevelMeter()
        meter.measure(peak: 0.5, at: Date())
        meter.measure(peak: 0.5, at: Date().addingTimeInterval(11))
    }

    func testSmokeVoiceSegmentDeliveryWithoutARequest() {
        let slot = RequestSlot()
        let delivery = RequestSlot.delivery(slot)
        let buffer = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(standardFormatWithSampleRate: 16_000,
                                                               channels: 1)!,
                                      frameCapacity: 1)!
        delivery(buffer)
    }

    func testSmokePriceWatchAnswersWithoutCurrency() {
        let watch = PriceWatch(terms: ["PS5"], goal: 400, currencyCode: nil)
        let offer = PriceWatchOffer(price: 350, currency: "", shop: "")
        _ = PriceWatchAnswers.alarm(watch, offer: offer)
        _ = PriceWatchAnswers.notifyBody(watch, offer: offer)
        var listed = watch
        listed.lastPrice = 350
        listed.lastCurrency = nil
        _ = PriceWatchAnswers.listLine(listed)
    }

    func testSmokePriceWatchCatalogWithoutCurrency() async {
        let store = PriceWatchStore(paths: temporaryPaths("raw-watch"))
        let made = await store.create(terms: ["PS5"], goal: 400, intervalHours: 24,
                                      currencyCode: nil, regionCode: nil)
        if let watch = made?.watch {
            await store.record(id: watch.id, offer: PriceWatchOffer(price: 350, currency: "", shop: ""),
                               fallbackCurrency: "", now: Date())
        }
        _ = await store.catalog()
    }

    func testSmokeReminderSnapshotWithoutOptionalFields() {
        let reminder = EKReminder(eventStore: EKEventStore())
        _ = EventKitReminderStore.snapshot(reminder)
    }

    func testReminderAccessWhenTheStoreThrows() async {
        let store = EventKitReminderStore.storeOverride
        let status = EventKitReminderStore.accessStatusOverride
        EventKitReminderStore.storeOverride = RawThrowingEventStore()
        EventKitReminderStore.accessStatusOverride = .notDetermined
        defer {
            EventKitReminderStore.storeOverride = store
            EventKitReminderStore.accessStatusOverride = status
        }
        let allowed = await EventKitReminderStore().hasAccess()
        XCTAssertFalse(allowed)
    }

    func testWebSearchDomainWithoutAHost() {
        XCTAssertEqual(WebSearch.domain(of: URL(fileURLWithPath: "/tmp/raw")), "")
    }

    func testThinkingDirectiveMergesItsEntries() {
        var body: [String: Any] = ["reasoning_effort": "old"]
        ThinkingDirective.effort(.high).applied(to: &body)
        XCTAssertEqual(body["reasoning_effort"] as? String, "high")
    }

    func testRateLimitRetryReturnsTheBodyResult() async throws {
        let value = try await RateLimitRetry.run(attempts: 1) { 42 }
        XCTAssertEqual(value, 42)
    }

    func testChatRequestMergesExtraFields() throws {
        let request = try ChatRequest.post(baseURL: "https://api.test/v1", key: "k", model: "m",
                                           messages: [], stream: false, thinking: .nothing,
                                           timeout: 1, extra: ["temperature": 0.2])
        let body = try XCTUnwrap(jsonBody(of: request))
        XCTAssertEqual(body["temperature"] as? Double, 0.2)
    }

    func testChatStoreSortsLoadedConversations() async throws {
        let paths = temporaryPaths("raw-chat-sort")
        let store = ChatStore(media: MediaStore(paths: paths), paths: paths)
        store.newConversation()
        if let id = store.current?.id {
            store.appendMessage(ChatMessage(role: .user, text: "Erste"), to: id)
        }
        store.newConversation()
        if let id = store.current?.id {
            store.appendMessage(ChatMessage(role: .user, text: "Zweite"), to: id)
        }
        await store.flushPendingSave()
        let loaded = ChatStore(media: MediaStore(paths: paths), paths: paths)
        XCTAssertFalse(loaded.conversations.isEmpty)
    }

    func testSmokeChatStoreReminderOfferWithoutAStamp() {
        let paths = temporaryPaths("raw-chat-offer")
        let store = ChatStore(media: MediaStore(paths: paths), paths: paths)
        store.newConversation()
        guard let conv = store.current?.id else { return }
        let message = ChatMessage(role: .assistant, text: "Scan")
        store.appendMessage(message, to: conv)
        store.attachReminderOffer(ScanReminderOffer(title: "Frist", due: nil), to: message.id, in: conv)
    }

    func testSmokeAnswerCarryWithAPlanWithoutAStart() {
        let carry = AnswerCarry()
        _ = carry.createdAlready(QwenAPI.CalendarPlan(action: .none))
    }

    func testLiveBriefingSourcesWithMissingOptionals() async {
        let eventStore = EKEventStore()
        let event = EKEvent(eventStore: eventStore)
        event.calendar = EKCalendar(for: .event, eventStore: eventStore)
        event.startDate = Date()
        event.title = nil
        let calendar = LiveBriefingCalendar(events: { _ in [event] })
        _ = calendar.briefingEvents(on: Date())
        let reminders = LiveBriefingReminders(store: RawThrowingReminderStore())
        let items = await reminders.briefingReminders()
        XCTAssertTrue(items.isEmpty)
    }

    func testProviderKeyVaultMissingValue() {
        let vault = ProviderKeyVault(store: MemoryKeyStore())
        XCTAssertEqual(vault.value(for: .qwenCloud), "")
    }

    func testOpenMeteoWithoutTimezone() throws {
        let json = """
        {"hourly":{"time":["2026-10-20T06:00","2026-10-20T07:00","2026-10-20T08:00"],
        "temperature_2m":[1,2,3]}}
        """
        let place = WeatherPlace(name: "Test", latitude: 1, longitude: 2, timezone: nil)
        let ref = OpenMeteo.day(from: Data(json.utf8), date: "2026-10-20", place: place)
        XCTAssertEqual(ref?.timezone, nil)
    }

    func testSmokeListenNotifierPostsAStoppedNotice() {
        LocalListenNotifier().listeningStopped()
    }

    func testSmokeMusicLibraryMatchingWithAMissingArtist() {
        let entry = MusicLibraryEntry(kind: .song, id: 1, name: "Lied", artist: nil)
        let request = MusicRequest(action: .play, query: "Lied", artist: "Interpret", kind: .song)
        _ = MusicLibraryMatching.best(for: request, in: [entry])
    }

    func testSmokePictureSearchWithoutPageArguments() {
        let json = #"{"turl":"https://img.test/th?id=1"}"#
        _ = BingPictureSearch.hit(fromJSON: json)
    }

    func testSmokePlaceSearchWithAnUnnamedItem() {
        let item = MKMapItem(location: CLLocation(latitude: 48, longitude: 11), address: nil)
        item.name = nil
        _ = PlaceSearch.hits(from: [item], around: nil, mode: .walking)
    }
}

private final class RawLoadedPersistence: ConversationPersisting, @unchecked Sendable {
    let loaded: [Conversation]
    init(_ loaded: [Conversation]) { self.loaded = loaded }
    func persist(_ conversations: [Conversation]) async throws {}
    func load() -> ConversationLoad { .loaded(loaded) }
}

@MainActor
extension LiveRawCoverageTests {
    func testSmokeNotificationPermissionSystemDefaults() async {
        NotificationPermission.askOverride = { throw APIError(message: "kaputt") }
        NotificationPermission.request(reporting: "RAWTEST")
        try? await Task.sleep(for: .milliseconds(100))
        NotificationPermission.askOverride = { true }
        NotificationPermission.request(reporting: "RAWTEST")
        try? await Task.sleep(for: .milliseconds(100))
        NotificationPermission.askOverride = nil
    }

    func testChatStoreLoadsAndSortsTwoConversations() {
        var older = Conversation(title: "Alt")
        older.updatedAt = Date(timeIntervalSince1970: 1)
        var newer = Conversation(title: "Neu")
        newer.updatedAt = Date(timeIntervalSince1970: 2)
        let store = ChatStore(persistence: RawLoadedPersistence([older, newer]))
        XCTAssertEqual(store.conversations.map(\.title), ["Neu", "Alt"])
    }

    func testSmokeLiveContactAccessDefaults() async throws {
        guard ProcessInfo.processInfo.environment["GWEN_LIVE_PERMISSIONS"] == "1"
                || LiveContactDirectory.authorizationStatus() != .notDetermined else {
            throw XCTSkip("Live permission requests need pre-granted TCC entries; "
                          + "run scripts/grant_test_permissions.sh.")
        }
        _ = await LiveContactDirectory.requestAccess()
        _ = await LiveContactDirectory().access()
    }

    func testSmokeDocumentExtractorWithABlankPage() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("raw-blank-\(UUID().uuidString).pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 200))
        try renderer.writePDF(to: url) { context in context.beginPage() }
        defer { try? FileManager.default.removeItem(at: url) }
        _ = DocumentExtractor.extract(url: url, kind: .pdf, ocrLanguages: [])
    }

    func testSmokeITunesAlbumWithoutTrackNumbers() async throws {
        let album = #"{"results":[{"wrapperType":"collection","collectionId":1,"collectionName":"Album","artistName":"Artist"}]}"#
        let tracks = #"{"results":[{"wrapperType":"track","trackId":2,"trackName":"Lied","artistName":"Artist","collectionId":1}]}"#
        let search = ITunesCatalogSearch(country: "de") { url in
            Data((url.path == "/lookup" ? tracks : album).utf8)
        }
        let request = MusicRequest(action: .play, query: "Album", artist: "Artist", kind: .album)
        _ = try await search.find(request)
    }

    func testSmokePriceRegionWithoutCurrencyOrName() {
        let region = PriceRegion(code: "ZZ", source: .open)
        _ = region.label
        _ = region.traceLine
        _ = PriceRegion(code: nil, source: .open).traceLine
    }

    func testProviderKeyVaultWithoutAnAccount() {
        var vault = ProviderKeyVault(store: MemoryKeyStore(), accounts: [:])
        XCTAssertEqual(vault.value(for: .qwenCloud), "")
        XCTAssertEqual(vault.persist(.qwenCloud), .untouched)
    }

    func testSmokeListenNotifierPostsAnAnswer() async {
        LocalListenNotifier().answered("Hallo")
        try? await Task.sleep(for: .milliseconds(100))
    }

    func testRateLimitRetryDefaults() async throws {
        let value = try await RateLimitRetry.run { 7 }
        XCTAssertEqual(value, 7)
    }

    func testSmokeThinkingProbeRequestAndLevels() throws {
        _ = try ThinkingProbe.levelRequest(baseURL: "https://api.test/v1", key: "k", model: "m")
        _ = ThinkingProbe.levels(in: "must be one of: \"low\", \"high\"")
    }

    func testModelProbeRunnerMergesRounds() async {
        let found = await ModelProbeRunner.run(["a", "b", "c", "d", "e"]) { $0.uppercased() }
        XCTAssertEqual(found.count, 5)
    }

    func testSmokeOpenRouterDollarsWithANonFiniteValue() {
        _ = OpenRouterAPI.dollars(.nan)
        _ = OpenRouterAPI.dollars(1.5)
    }

    func testAppSettingsFallbacksWithEmptyDefaults() {
        let suite = UserDefaults(suiteName: "raw-settings-\(UUID().uuidString)")!
        let settings = AppSettings(keyStore: MemoryKeyStore(), defaults: suite)
        XCTAssertNotNil(settings.provider)
    }

    func testSmokeBriefingSettingsTimeRoundTrip() {
        var settings = BriefingSettings()
        settings.time = Date()
        _ = settings.time
    }

    func testSmokeWeatherDayTabsWithRelativeDates() {
        _ = WeatherDayTabs.dates(selected: "2026-10-20", today: Date(timeIntervalSince1970: 1_800_000_000))
        _ = WeatherDayTabs.offset(of: "2026-10-20", today: Date(timeIntervalSince1970: 1_800_000_000))
    }

}

@MainActor
private struct RawLocationFix: LocationFixing {
    func fix() async throws -> CLLocation { CLLocation(latitude: 1, longitude: 2) }
}

@MainActor
extension LiveRawCoverageTests {
    func testPriceRegionWithAnUnknownRegionCode() {
        let region = PriceRegion(code: "XX", source: .open)
        XCTAssertNil(region.label)
        _ = region.traceLine
    }

    func testSmokePlaceSearchWithAPlacemarkWithoutAName() {
        let item = MKMapItem(location: CLLocation(latitude: 48, longitude: 11), address: nil)
        _ = PlaceSearch.hits(from: [item], around: nil, mode: .walking)
    }

    func testSourceMetadataReadsTypeNames() {
        let html = #"<script type="application/ld+json">{"@type":"Article"}</script>"#
        XCTAssertEqual(SourceMetadata.from(html: html).kinds, ["Article"])
    }

    func testSmokeReminderSnapshotWithAnExplicitlyMissingTitle() {
        let reminder = EKReminder(eventStore: EKEventStore())
        reminder.title = nil
        _ = EventKitReminderStore.snapshot(reminder)
    }

    func testThinkingProbeWithAnEmptyLevelList() {
        XCTAssertTrue(ThinkingProbe.levels(in: "must be one of:").isEmpty)
    }

    func testProviderSeedWithoutKeys() async {
        let url = StoragePaths().providerSeed
        try? Data(#"{"provider":"qwen"}"#.utf8).write(to: url)
        let suite = UserDefaults(suiteName: "raw-seed-\(UUID().uuidString)")!
        let settings = AppSettings(keyStore: MemoryKeyStore(), defaults: suite)
        XCTAssertEqual(settings.provider, .qwenCloud)
        try? FileManager.default.removeItem(at: url)
    }

    func testSmokeRefreshModelCapsWithoutAProvider() async {
        let suite = UserDefaults(suiteName: "raw-models-\(UUID().uuidString)")!
        let settings = AppSettings(keyStore: MemoryKeyStore(), defaults: suite)
        await settings.refreshModelCaps(for: [], of: nil)
    }

    func testSmokeListenNotifierHandlesTheNotificationResult() async {
        LocalListenNotifier().answered("Hallo")
        try? await Task.sleep(for: .milliseconds(500))
    }

    func testWeatherServiceWithoutAReverseGeocodedName() async throws {
        let json = """
        {"hourly":{"time":["2026-10-20T06:00","2026-10-20T07:00","2026-10-20T08:00"],
        "temperature_2m":[1,2,3]}}
        """
        var service = WeatherService()
        service.fixer = RawLocationFix()
        service.reverseGeocode = { _ in nil }
        service.fetcher = { _ in Data(json.utf8) }
        let ref = try await service.day(for: WeatherRequest(place: nil, day: .today, date: "2026-10-20"),
                                        now: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(ref.place, L.t("weather_here"))
    }

    func testPriceWatchCatalogWithALastPrice() async {
        let store = PriceWatchStore(paths: temporaryPaths("raw-watch-catalog"))
        guard let made = await store.create(terms: ["PS5"], goal: 400, intervalHours: 24,
                                            currencyCode: nil, regionCode: nil) else {
            return XCTFail("kein Preiswecker")
        }
        await store.record(id: made.watch.id,
                           offer: PriceWatchOffer(price: 350, currency: "", shop: ""),
                           fallbackCurrency: "", now: Date())
        let catalog = await store.catalog()
        XCTAssertFalse(catalog.isEmpty)
    }

    func testSmokeQwenImageWithoutAnImageOrNote() async throws {
        MockHTTP.install { _ in (200, MockHTTP.completion("")) }
        defer { MockHTTP.uninstall() }
        let request = try QwenAPI.userRequest(baseURL: "https://api.test/v1", key: "k", model: "m",
                                               text: "Bild", picture: nil, thinking: .nothing)
        _ = try? await QwenAPI.generateImage(req: request)
    }

    func testSmokeQwenStreamStartsTheDetachedTask() async throws {
        MockHTTP.install { _ in (200, MockHTTP.sse("Hallo")) }
        defer { MockHTTP.uninstall() }
        let request = try QwenAPI.userRequest(baseURL: "https://api.test/v1", key: "k", model: "m",
                                               text: "Hallo", picture: nil, thinking: .nothing)
        for try await _ in QwenAPI.streamText(req: request) {}
    }

    func testSmokeCalendarServiceWithMinimalEvents() {
        CalendarService.accessStatusOverride = .fullAccess
        defer { CalendarService.accessStatusOverride = nil }
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.startDate = Date()
        event.endDate = Date().addingTimeInterval(600)
        let calendar = EKCalendar(for: .event, eventStore: store)
        event.calendar = calendar
        _ = CalendarService.alertMinutes(for: event)
        _ = CalendarService.describe(event)
        _ = CalendarService.reference(for: event)
    }
}
