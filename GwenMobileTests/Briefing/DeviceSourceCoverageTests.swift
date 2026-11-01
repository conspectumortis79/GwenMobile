@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import CoreLocation
import EventKit
import MediaPlayer
import XCTest
import GwenMobileKit
@testable import GwenMobileProbes

private struct FailingFixer: LocationFixing {
    func fix() async throws -> CLLocation {
        throw APIError(message: "kein ort")
    }
}

private struct DeviceFixer: LocationFixing {
    func fix() async throws -> CLLocation {
        CLLocation(latitude: 48.137, longitude: 11.575)
    }
}

@MainActor
final class DeviceSourceCoverageTests: GwenTestCase {
    override func tearDown() {
        MockHTTP.uninstall()
        super.tearDown()
    }

    func testThePlanAskerParsesRetriesAndGivesUp() async {
        let good = payload(ToolRouter.answerTool, "{}")
        let parsed = await ToolRouter.plan(asking: { good })
        XCTAssertEqual(parsed.map(\.stepKind), [.chat])
        let text = ToolCallPayload.message([], content: "nur text")
        let nothing = await ToolRouter.plan(asking: { text }, attempts: 2)
        XCTAssertTrue(nothing.isEmpty)
        let failing = await ToolRouter.plan(asking: { throw APIError(message: "kaputt") })
        XCTAssertTrue(failing.isEmpty)
        XCTAssertTrue(ToolRouter.answerShape(of: text).contains("ende="))
        XCTAssertEqual(ToolRouter.answerShape(of: Data("kaputt".utf8)), "antwort_unlesbar")
    }

    func testTheScanReminderAsksTheModel() async {
        let reply = payload(ToolRouter.reminderTool, #"{"action":"create","title":"Milch"}"#)
        MockHTTP.install { _ in (200, reply) }

        let decision = await ToolRouter.scanReminder(baseURL: "https://q.test/v1", key: "k", model: "m",
                                                     text: "Scanne", context: SendContext(scannedDocument: true),
                                                     history: [], document: "Rechnung", thinking: .nothing)
        XCTAssertEqual(decision?.stepKind, .reminder)
        let answer = payload(ToolRouter.answerTool, "{}")
        MockHTTP.install { _ in (200, answer) }
        let none = await ToolRouter.scanReminder(baseURL: "https://q.test/v1", key: "k", model: "m",
                                                 text: "Scanne", context: SendContext(),
                                                 history: [], document: "x", thinking: .nothing)
        XCTAssertNil(none)
    }

    func testTheCameraPresenterWithoutAHardwareCamera() async {
        let previousAvailability = CameraPresenter.isCameraAvailable
        CameraPresenter.isCameraAvailable = { false }
        defer { CameraPresenter.isCameraAvailable = previousAvailability }
        let presenter = CameraPresenter()
        _ = presenter.isAvailable
        let capture = await presenter.capture()
        XCTAssertNil(capture)
        presenter.present()
        presenter.imagePickerControllerDidCancel(UIImagePickerController())
        presenter.imagePickerController(UIImagePickerController(), didFinishPickingMediaWithInfo: [:])
        var received: UIImage?
        presenter.onImage = { received = $0 }
        presenter.imagePickerController(UIImagePickerController(),
                                        didFinishPickingMediaWithInfo: [.originalImage: UIImage()])
        try? await Task.sleep(for: .milliseconds(350))
        XCTAssertNotNil(received)
    }

    func testTheLiveContactDirectoryWithoutAccess() async {
        let directory = LiveContactDirectory()
        LiveContactDirectory.authorizationStatus = { .denied }
        let access = await directory.access()
        XCTAssertEqual(access, .denied)
        XCTAssertFalse(ContactCardReader.keys.isEmpty)
    }

    #if !targetEnvironment(macCatalyst)
    func testTheMediaLibraryReaderReturnsEntriesOrNothing() async {
        let reader = MediaLibraryReader()
        let entries = await reader.entries(of: [.playlist, .artist, .album, .song, .any])
        XCTAssertTrue(entries.allSatisfy { !$0.name.isEmpty })
        XCTAssertTrue(MediaLibraryIndex.entries(of: .any).isEmpty)
    }

    func testTheSystemMusicAppHelpers() async {
        let app = SystemMusicApp()
        _ = app.isPlaying
        app.perform(.pause)
        app.perform(.next)
        app.perform(.previous)
        app.perform(.play)
        app.perform(.resume)
        XCTAssertEqual(SystemMusicApp.property(of: .artist), MPMediaItemPropertyArtistPersistentID)
        XCTAssertEqual(SystemMusicApp.property(of: .album), MPMediaItemPropertyAlbumPersistentID)
        XCTAssertEqual(SystemMusicApp.property(of: .song), MPMediaItemPropertyPersistentID)
        XCTAssertEqual(SystemMusicApp.property(of: .playlist), MPMediaItemPropertyPersistentID)
        XCTAssertEqual(SystemMusicApp.property(of: .any), MPMediaItemPropertyPersistentID)
        let entry = MusicLibraryEntry(kind: .song, id: 1, name: "Nichts")
        _ = await app.play(entry)
        _ = await app.play(storeIDs: ["1"])
    }
    #endif

    func testTheOnDeviceTranslationHelpers() async {
        let missing = await OnDeviceTranslation.status(for: TranslationJob(text: "Hallo", targetCode: "xx"))
        XCTAssertEqual(missing, .unsupportedPair)
        let pair = await OnDeviceTranslation.status(for: TranslationJob(text: "Hallo", targetCode: "fr"))
        XCTAssertTrue([.ready, .packMissing, .unsupportedPair].contains(pair))
        do {
            _ = try await OnDeviceTranslation.translate(TranslationJob(text: "   ", targetCode: "fr"))
            XCTFail("erwartet Fehler")
        } catch {}
        #if DEBUG
        _ = await OnDeviceTranslation.supportedCodes()
        #endif
    }

    func testTheLiveBriefingSources() async {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = "Zahnarzt"
        event.startDate = Date()
        event.endDate = Date().addingTimeInterval(3600)
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = "Privat"
        event.calendar = calendar
        let liveCalendar = LiveBriefingCalendar(events: { _ in [event] })
        let mapped = liveCalendar.briefingEvents(on: Date())
        XCTAssertEqual(mapped.first?.title, "Zahnarzt")
        XCTAssertEqual(mapped.first?.calendar, "Privat")
        let reminderStore = ProbeReminderStore()
        reminderStore.stored = [StoredReminder(id: "r1", title: "Milch", list: "Einkauf")]
        let reminders = LiveBriefingReminders(store: reminderStore)
        let open = await reminders.briefingReminders()
        XCTAssertEqual(open.first?.title, "Milch")
        var service = WeatherService()
        service.fixer = DeviceFixer()
        service.reverseGeocode = { _ in "München" }
        let today = Formatters.stamp(Date())
        service.fetcher = { _ in ForecastFixture.json(date: today) }
        let weather = LiveBriefingWeather(service: service)
        let ref = try? await weather.briefingWeather(dayOffset: 0)
        XCTAssertEqual(ref?.hours.count, 17)
        let travel = LiveBriefingTravel(fixer: FailingFixer())
        let none = await travel.briefingTravel(to: "Büro", departure: Date())
        XCTAssertNil(none)
        let blank = await LiveBriefingTravel().briefingTravel(to: "   ", departure: Date())
        XCTAssertNil(blank)
    }
}
