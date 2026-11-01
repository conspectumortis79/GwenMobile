@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import GwenMobileKit
@testable import GwenMobileProbes
import AVFoundation
import XCTest

@MainActor
final class LiveSmallLogicTests: GwenTestCase {
    func testTheTimerAndVoiceHelpers() {
        XCTAssertEqual(TimerAnswer.title(TimerRequest(minutes: 1, seconds: 0, title: "  ")),
                       L.t("timer_default_title"))
        XCTAssertEqual(TimerAnswer.title(TimerRequest(title: "Tee")), "Tee")
        XCTAssertFalse(TimerAnswer.duration(90).isEmpty)
        XCTAssertFalse(TimerAnswer.result(.denied, request: TimerRequest()).isEmpty)
        XCTAssertFalse(RecordingSetup.preferred.isEmpty)
        let option = VoiceOption(id: "x", name: "Anna (Deutsch)", language: "de-DE")
        XCTAssertEqual(VoiceOption.baseName("Anna (Deutsch)"), "Anna")
        XCTAssertFalse(option.label(defaultLanguage: "en-US").isEmpty)
        _ = VoiceOption.regionName(of: "de-DE")
        _ = VoiceCatalog.defaultLanguage(for: .de)
        _ = VoiceCatalog.defaultVoiceName(for: .de)
        _ = VoiceCatalog.defaultLabel(for: .de)
        _ = VoiceCatalog.options(for: .de)
        _ = VoiceCatalog.sorted([option], defaultLanguage: "de-DE")
        _ = VoiceCatalog.voice(identifier: "", language: .de)
    }

    func testTheBriefingSettingsAndAudioMeter() {
        var settings = BriefingSettings()
        let time = settings.time
        settings.time = time
        XCTAssertFalse(settings.includes.weather == false && settings.includes.travel == false)
        settings.enabled = true
        settings.store()
        XCTAssertFalse(BriefingSettings.load().time.timeIntervalSince1970.isNaN)
        _ = settings.normalized
        let meter = AudioLevelMeter { _ in }
        meter.measure(peak: 0.5, at: Date())
        meter.measure(peak: 0.5, at: Date().addingTimeInterval(AudioLevelMeter.window + 1))
        XCTAssertEqual(AudioLevelMeter.decibels(0), AudioLevelMeter.floor)
        XCTAssertLessThanOrEqual(AudioLevelMeter.decibels(1), 0)
    }

    func testTheRegionMessagingAndCalendarChoices() {
        _ = PriceRegion.device().label
        _ = PriceRegion.located("DE").traceLine
        _ = PriceRegion.named("DE")
        _ = PriceRegion.claimed("DE", in: "Preis in DE")
        _ = PriceRegion.named(nil)
        let capability = MessagingCapability(entitled: true, carrierAvailable: true)
        XCTAssertTrue(capability.direct)
        XCTAssertFalse(capability.trace.isEmpty)
        _ = MessagingChoice.capability(carrierAvailable: true)
        _ = MessagingChoice.current()
        _ = MessagingChoice.sender(for: capability)
        XCTAssertEqual(CalendarChoice.resolve(requested: nil, available: [], deviceDefault: nil,
                                              silent: .keepCurrent), .keep)
        XCTAssertEqual(CalendarChoice.resolve(requested: "Privat", available: ["Privat"],
                                              deviceDefault: nil, silent: .keepCurrent), .title("Privat"))
        XCTAssertEqual(CalendarChoice.resolve(requested: "Fehlt", available: ["Privat"],
                                              deviceDefault: nil, silent: .keepCurrent), .unmatched("Fehlt"))
        XCTAssertEqual(CalendarChoice.normalize("Ärztin"), "arztin")
    }

    func testThePriceHelpersAndAnswers() {
        var watch = PriceWatch(terms: ["PS5"], goal: 400, wording: "PS5 Slim", currencyCode: "EUR")
        watch.lastPrice = 379
        watch.lastCurrency = "EUR"
        watch.lastShop = "MediaMarkt"
        let offer = PriceWatchOffer(price: 379, currency: "EUR", shop: "MediaMarkt",
                                    url: "https://shop.test/ps5", product: "PS5")
        XCTAssertFalse(watch.product.isEmpty)
        XCTAssertFalse(watch.shortKey.isEmpty)
        XCTAssertNotNil(watch.status)
        XCTAssertNotNil(watch.nextDue)
        _ = PriceWatchReport(arguments: #"{"price":379,"product":"PS5","source":1}"#)
        _ = PriceWatchReport(arguments: #"{"price":"379,50","product":123,"source":"1"}"#)
        XCTAssertFalse(PriceWatchAnswers.alarm(watch, offer: offer).isEmpty)
        XCTAssertFalse(PriceWatchAnswers.listLine(watch).isEmpty)
        XCTAssertFalse(PriceWatchAnswers.notifyBody(watch, offer: offer).isEmpty)
    }

    func testTheOpenMeteoAndCitationHelpers() {
        XCTAssertNil(OpenMeteo.day(from: Data("{}".utf8), date: "2026-10-05",
                                   place: WeatherPlace(name: "München", latitude: 48, longitude: 11,
                                                       timezone: nil)))
        let ref = WeatherFixture.ref(hours: WeatherFixture.day { WeatherFixture.hour($0) })
        XCTAssertEqual(OpenMeteo.day(from: ForecastFixture.json(date: ref.day), date: ref.day,
                                     place: ref.placeValue)?.hours.count, ref.hours.count)
        XCTAssertEqual(CitationMarkers.shifted("A [1] B [2]", by: 1, sources: 2), "A [2] B [3]")
        XCTAssertEqual(CitationMarkers.shifted("A [9]", by: 1, sources: 2), "A [9]")
        XCTAssertEqual(CitationMarkers.shifted("A", by: 0, sources: 2), "A")
    }

    func testTheHTTPErrorPaths() {
        let response = URLResponse(url: URL(string: "https://x.test")!, mimeType: nil,
                                   expectedContentLength: 0, textEncodingName: nil)
        XCTAssertNoThrow(try HTTP.ensureSuccess(response))
        XCTAssertNoThrow(try HTTP.ensureAPISuccess(response, data: Data()))
        let bad = HTTPURLResponse(url: URL(string: "https://x.test")!, statusCode: 500,
                                  httpVersion: nil, headerFields: nil)!
        XCTAssertThrowsError(try HTTP.ensureSuccess(bad))
        XCTAssertThrowsError(try HTTP.ensureAPISuccess(bad, data: Data("kaputt".utf8)))
    }

    func testTheChatStoreTitleAndReminderOffer() throws {
        XCTAssertEqual(ChatStore.title(of: "\n\n Erste Zeile \nZweite"), "Erste Zeile")
        XCTAssertEqual(ChatStore.title(of: ""), "")
        let paths = temporaryPaths("small-chat")
        let store = ChatStore(media: MediaStore(paths: paths), paths: paths)
        store.newConversation()
        let convID = try XCTUnwrap(store.current?.id)
        let message = ChatMessage(role: .assistant, text: "Antwort")
        store.appendMessage(message, to: convID)
        let offer = ScanReminderOffer(title: "Zahlen", due: Date().addingTimeInterval(3600))
        store.attachReminderOffer(offer, to: message.id, in: convID)
        XCTAssertNotNil(store.current?.messages.first?.reminderOffer)
        store.attachReminderOffer(offer, to: UUID(), in: convID)
        store.attachReminderOffer(offer, to: message.id, in: UUID())
    }

    func testTheReminderChipOutcomes() {
        let stored = StoredReminder(id: "r1", title: "Zahlen", list: "Liste")
        let ref = ReminderRef(stored)
        XCTAssertEqual(ReminderChip.outcome(for: ref, hasAccess: true, isLive: { _ in true }),
                       .present(ref))
        XCTAssertEqual(ReminderChip.outcome(for: ref, hasAccess: false, isLive: { _ in true }),
                       .accessMissing)
        XCTAssertEqual(ReminderChip.outcome(for: ref, hasAccess: true, isLive: { _ in false }),
                       .gone)
        XCTAssertNil(ReminderChip.noticeKey(for: .present(ref)))
        XCTAssertEqual(ReminderChip.noticeKey(for: .accessMissing), "rem_denied")
        XCTAssertEqual(ReminderChip.noticeKey(for: .gone), "rem_chip_gone")
    }
}
