@testable import GwenMobileFeatureCore
import GwenMobileKit
import CoreLocation
import EventKit
import XCTest

@MainActor
final class PortDefaultsTests: GwenTestCase {
    func testTheMessagePortsAreTestSafe() async {
        XCTAssertNil(MessageSenderPort.carrier())
        let sender = MessageSenderPort.compose()
        XCTAssertEqual(sender.way, "stub")
        let number = try? XCTUnwrap(DialNumber("030123456"))
        let result = await sender.send("Hallo", to: number!)
        XCTAssertEqual(result, .unavailable)
    }

    func testTheMusicGeocoderReminderAndWeatherDefaults() async {
        let app = MusicAppPort.current
        XCTAssertFalse(app.isPlaying)
        let played = await app.play(MusicLibraryEntry(kind: .song, id: 1, name: "Lied"))
        XCTAssertFalse(played)
        let stored = await app.play(storeIDs: ["1", "2"])
        XCTAssertFalse(stored)
        app.perform(.pause)
        let geocoder = CountryGeocoderPort.current
        let country = try? await geocoder.country(at: CLLocation(latitude: 1, longitude: 2))
        XCTAssertNil(country)
        let place = await ReminderPlacePort.current.locate("Berlin")
        XCTAssertNil(place)
        let geocode = await WeatherService.defaultGeocode("Berlin")
        XCTAssertNil(geocode)
        let local = await WeatherService.defaultLocalSearch("Berlin")
        XCTAssertNil(local)
        let reverse = await WeatherService.defaultReverseGeocode(CLLocation(latitude: 1, longitude: 2))
        XCTAssertNil(reverse)
    }

    func testTheDeviceTranslationDefaults() async {
        let job = TranslationJob(text: "Hallo", targetCode: "fr")
        let status = await OnDeviceTranslation.liveStatus(job)
        XCTAssertEqual(status, .unsupportedPair)
        let codes = await OnDeviceTranslation.liveSupportedCodes()
        XCTAssertTrue(codes.isEmpty)
        do {
            _ = try await OnDeviceTranslation.batch(["Hallo"], Locale.Language(identifier: "de"),
                                                     Locale.Language(identifier: "fr"))
            XCTFail("erwartet Fehler")
        } catch {}
    }

    func testSmokeTheVoiceHardwareDefaults() async throws {
        let tap = VoiceHardwarePort.makeTap()
        try await tap.start { _ in }
        tap.stop()
        VoiceHardwarePort.makeDisruptions().start { _ in }
        VoiceHardwarePort.makeDisruptions().stop()
        VoiceHardwarePort.makeHeadsets().start()
        VoiceHardwarePort.makeHeadsets().stop()
    }

    func testTheReminderStoreStub() async throws {
        let store = StubReminderEventStore()
        XCTAssertNotNil(store.makeReminder())
        XCTAssertNotNil(store.makeCalendar())
        let fetched = await store.fetchReminders()
        XCTAssertTrue(fetched.isEmpty)
        XCTAssertNil(store.calendarItem(withIdentifier: "x"))
        XCTAssertTrue(store.calendars(for: .reminder).isEmpty)
        XCTAssertNil(store.defaultCalendarForNewReminders())
        try store.save(EKReminder(eventStore: EKEventStore()), commit: false)
        try store.remove(EKReminder(eventStore: EKEventStore()), commit: false)
        try store.saveCalendar(EKCalendar(for: .reminder, eventStore: EKEventStore()), commit: false)
        XCTAssertTrue(store.sources.isEmpty)
        let access = try await store.requestFullAccessToReminders()
        XCTAssertFalse(access)
    }
}
