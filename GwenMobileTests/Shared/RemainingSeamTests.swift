@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import Contacts
import CoreLocation
import EventKit
import MapKit
import SwiftUI
import UIKit
import XCTest
import GwenMobileKit

@MainActor
final class RemainingSeamTests: GwenTestCase {
    func testSmokeTheLiveWeatherDefaults() async {
        _ = await WeatherSystem.liveGeocode("Berlin")
        _ = await WeatherSystem.liveLocalSearch("Berlin")
        _ = await WeatherSystem.liveReverseGeocode(CLLocation(latitude: 52.52, longitude: 13.405))
    }

    func testTheLiveReminderStorePrimitives() async {
        let store = LiveReminderEventStore.shared
        _ = store.makeCalendar()
        _ = store.makeReminder()
        _ = store.calendars(for: .reminder)
        _ = store.defaultCalendarForNewReminders()
        _ = store.sources
        _ = store.calendarItem(withIdentifier: "unbekannt")
        _ = await store.fetchReminders()
        let reminder = store.makeReminder()
        do { try store.save(reminder, commit: true) } catch {}
        do { try store.remove(reminder, commit: true) } catch {}
        let calendar = store.makeCalendar()
        do { try store.saveCalendar(calendar, commit: true) } catch {}
        _ = EventKitReminderStore.writableLists()
        _ = EventKitReminderStore.candidateSources()
        XCTAssertFalse(EventKitReminderStore.isLive(""))
    }

    func testTheFakeStoreCalendarLookups() {
        let fake = FakeReminderEventStore()
        let calendar = EKCalendar(for: .reminder, eventStore: EKEventStore())
        calendar.title = "Privat"
        fake.calendarList = [calendar]
        fake.defaultCalendar = nil
        EventKitReminderStore.storeOverride = fake
        defer { EventKitReminderStore.storeOverride = nil }
        XCTAssertEqual(try? EventKitReminderStore.calendar(named: "Privat").title, "Privat")
        XCTAssertEqual(try? EventKitReminderStore.calendar(named: nil).title, "Privat")
        fake.calendarList = []
        do {
            _ = try EventKitReminderStore.makeDefaultList()
            XCTFail("erwartet Fehler")
        } catch {}
    }

    func testTheLiveContactSources() throws {
        _ = LiveContactDirectory.authorizationStatus()
        XCTAssertFalse(ContactCardReader.keys.isEmpty)
    }

    func testThePlaceDefaults() async {
        let item = NearbyPlace.mapItem(name: "Museum", latitude: 48.2, longitude: 11.6)
        XCTAssertEqual(item.name, "Museum")
        let request = PlaceSearch.request(for: "Apotheke", origin: nil)
        _ = try? await LivePlaceSearch.searchRunnerDefault(request)
    }

}
