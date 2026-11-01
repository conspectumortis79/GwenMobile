@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import Contacts
import CoreLocation
import EventKit
import MapKit
import MediaPlayer
import Photos
import UIKit
import XCTest
import GwenMobileKit
@testable import GwenMobileProbes

private struct SeamLocationFixer: LocationFixing {
    func fix() async throws -> CLLocation {
        CLLocation(latitude: 48.137, longitude: 11.575)
    }
}

private final class FakeContactSource: ContactCardSource {
    var groups: [(id: String, name: String)] = []
    var members: [String: [CNContact]] = [:]
    var contacts: [CNContact] = []
    var failure: Error?

    func contactGroups() throws -> [(id: String, name: String)] {
        if let failure { throw failure }
        return groups
    }

    func contactMembers(ofGroup id: String) throws -> [CNContact] { members[id] ?? [] }

    func allContacts() throws -> [CNContact] {
        if let failure { throw failure }
        return contacts
    }
}

@MainActor
final class SeamCoverageTests: GwenTestCase {
    private func contact(_ given: String, _ family: String) -> CNContact {
        let person = CNMutableContact()
        person.givenName = given
        person.familyName = family
        person.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile,
                                              value: CNPhoneNumber(stringValue: "0171 123"))]
        return person.copy() as? CNContact ?? CNContact()
    }

    func testThePhotoLibrarySeams() async {
        SystemPhotoLibrary.authorization = { .authorized }
        SystemPhotoLibrary.performChanges = { _ in true }
        let library = SystemPhotoLibrary()
        let allowed = await library.allowsWriting()
        XCTAssertTrue(allowed)
        let added = await library.add(UIImage())
        XCTAssertTrue(added)
        SystemPhotoLibrary.authorization = { .limited }
        _ = await library.allowsWriting()
        SystemPhotoLibrary.authorization = { .denied }
        let refused = await library.allowsWriting()
        XCTAssertFalse(refused)
        SystemPhotoLibrary.performChanges = { _ in false }
        let failed = await library.add(UIImage())
        XCTAssertFalse(failed)
    }

    func testTheContactDirectorySeams() async {
        LiveContactDirectory.authorizationStatus = { .authorized }
        let directory = LiveContactDirectory()
        var access = await directory.access()
        XCTAssertEqual(access, .granted)
        LiveContactDirectory.authorizationStatus = { .limited }
        access = await directory.access()
        XCTAssertEqual(access, .granted)
        LiveContactDirectory.authorizationStatus = { .notDetermined }
        LiveContactDirectory.requestAccess = { true }
        access = await directory.access()
        XCTAssertEqual(access, .granted)
        LiveContactDirectory.requestAccess = { false }
        access = await directory.access()
        XCTAssertEqual(access, .denied)
        LiveContactDirectory.authorizationStatus = { .denied }
        access = await directory.access()
        XCTAssertEqual(access, .denied)

        let person = contact("Mia", "Muster")
        let source = FakeContactSource()
        source.groups = [("g1", "Familie")]
        source.members = ["g1": [person]]
        source.contacts = [person]
        let cards = try? ContactCardReader.read(from: source)
        XCTAssertEqual(cards?.count, 1)
        let memberships = try? ContactCardReader.memberships(in: source)
        XCTAssertEqual(memberships?[person.identifier], ["Familie"])
        source.failure = APIError(message: "kaputt")
        do {
            _ = try ContactCardReader.read(from: source)
            XCTFail("erwartet Fehler")
        } catch {}
        do {
            _ = try ContactCardReader.memberships(in: source)
            XCTFail("erwartet Fehler")
        } catch {}
        _ = ContactCardReader.keys
    }

    func testThePlaceSeams() async {
        NearbyPlace.mapItemOpener = { _, _ in true }
        let place = NearbyPlace(name: "Apotheke", latitude: 48.1, longitude: 11.5, metres: 100)
        XCTAssertTrue(place.openRoute())
        NearbyPlace.mapItemOpener = { _, _ in false }
        URLOpenSpy.install()
        URLOpenSpy.opened = []
        XCTAssertTrue(place.openRoute())
        URLOpenSpy.uninstall()
        NearbyPlace.mapItemOpener = { item, options in item.openInMaps(launchOptions: options) }

        let item = MKMapItem(location: CLLocation(latitude: 48.1, longitude: 11.5), address: nil)
        item.name = "Apotheke"
        LivePlaceSearch.searchRunner = { _ in [item] }
        let search = LivePlaceSearch(fixer: SeamLocationFixer())
        let hits = try? await search.places(matching: ["Apotheke"], wish: "Apotheke", mode: .walking)
        XCTAssertFalse(hits?.isEmpty ?? true)
        let route = try? await search.route(to: ["Museum"], wish: "Museum", mode: .cycling)
        XCTAssertFalse(route?.isEmpty ?? true)
        LivePlaceSearch.searchRunner = { _ in [] }
        _ = try? await search.places(matching: ["Nichts"], wish: "", mode: .walking)
        LivePlaceSearch.searchRunner = { request in
            try await LivePlaceSearch.searchRunnerDefault(request)
        }
        _ = try? await search.places(matching: [], wish: "", mode: .walking)
    }

    func testTheBriefingTravelSeams() async {
        let travel = LiveBriefingTravel(fixer: SeamLocationFixer())
        LiveBriefingTravel.geocode = { _ in CLLocationCoordinate2D(latitude: 48.2, longitude: 11.6) }
        LiveBriefingTravel.travelMinutes = { _, _, _, _ in 12 }
        let found = await travel.briefingTravel(to: "Museum", departure: Date())
        XCTAssertEqual(found?.carMinutes, 12)
        LiveBriefingTravel.travelMinutes = { from, to, type, departure in
            await LiveBriefingTravel.travelMinutesDefault(from, to, type, departure)
        }
        _ = await travel.briefingTravel(to: "Museum", departure: Date())
        LiveBriefingTravel.geocode = { _ in nil }
        _ = await travel.briefingTravel(to: "Nirgendwo", departure: Date())
        LiveBriefingTravel.geocode = { _ in nil }
        _ = await travel.briefingTravel(to: "  ", departure: Date())
        LiveBriefingTravel.geocode = { place in try await LiveBriefingTravel.geocodeDefault(place) }
        _ = try? await LiveBriefingTravel.geocode("Berlin")
        do {
            _ = try await travel.coordinate(of: "Nirgendwo")
        } catch {}
        let reminders = LiveBriefingReminders(store: ProbeReminderStore())
        _ = await reminders.briefingReminders()
        let weather = LiveBriefingWeather(service: WeatherFixture.service())
        _ = try? await weather.briefingWeather(dayOffset: 0)
    }

    #if !targetEnvironment(macCatalyst)
    func testTheMediaLibrarySeams() async {
        MediaLibraryReader.authorizationStatus = { .authorized }
        let reader = MediaLibraryReader()
        var access = await reader.access()
        XCTAssertTrue(access)
        MediaLibraryReader.authorizationStatus = { .notDetermined }
        MediaLibraryReader.requestAuthorization = { .authorized }
        access = await reader.access()
        XCTAssertTrue(access)
        MediaLibraryReader.requestAuthorization = { .denied }
        access = await reader.access()
        XCTAssertFalse(access)
        MediaLibraryReader.authorizationStatus = { .denied }
        access = await reader.access()
        XCTAssertFalse(access)
        MediaLibraryIndex.playlists = { [] }
        MediaLibraryIndex.artists = { [] }
        MediaLibraryIndex.albums = { [] }
        MediaLibraryIndex.songs = { [] }
        let entries = await reader.entries(of: [.playlist, .artist, .album, .song, .any])
        XCTAssertTrue(entries.isEmpty)

        let playlists: [RawPlaylist] = [RawPlaylist(id: 1, name: "Liste"),
                                        RawPlaylist(id: 2, name: nil)]
        let artists: [RawArtist] = [RawArtist(id: 3, name: "Band"), RawArtist(id: 4, name: nil)]
        let albums: [RawAlbum] = [RawAlbum(id: 5, title: "Album", artist: "Band"),
                                  RawAlbum(id: 6, title: nil, artist: nil)]
        let songs: [RawSong] = [RawSong(id: 7, title: "Lied", artist: "Band"),
                                RawSong(id: 8, title: nil, artist: nil)]
        MediaLibraryIndex.playlists = { playlists }
        MediaLibraryIndex.artists = { artists }
        MediaLibraryIndex.albums = { albums }
        MediaLibraryIndex.songs = { songs }
        XCTAssertEqual(MediaLibraryIndex.entries(of: .playlist).count, 1)
        XCTAssertEqual(MediaLibraryIndex.entries(of: .artist).count, 1)
        XCTAssertEqual(MediaLibraryIndex.entries(of: .album).count, 1)
        XCTAssertEqual(MediaLibraryIndex.entries(of: .song).count, 1)
        XCTAssertTrue(MediaLibraryIndex.entries(of: .any).isEmpty)
        _ = MediaLibraryIndex.playlists()
        _ = MediaLibraryIndex.artists()
        _ = MediaLibraryIndex.albums()
        _ = MediaLibraryIndex.songs()
        MediaLibraryIndex.playlists = { [] }
        MediaLibraryIndex.artists = { [] }
        MediaLibraryIndex.albums = { [] }
        MediaLibraryIndex.songs = { [] }
    }
    #endif
}
