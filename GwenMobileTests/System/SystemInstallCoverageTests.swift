@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import AVFoundation
import CoreLocation
import EventKit
import MapKit
import UIKit
import UserNotifications
import VisionKit
import XCTest
import GwenMobileKit
#if canImport(AlarmKit)
import AlarmKit
#endif

#if !targetEnvironment(macCatalyst)

@MainActor
final class SystemInstallCoverageTests: GwenTestCase {
    func testTheInstallWiresAndRunsEveryLiveAdapter() async throws {
        let closer = ShareCloserPort.make
        defer { ShareCloserPort.make = closer }

        DeviceSystems.install()

        XCTAssertTrue(TimerSetterPort.current is SystemTimerSetter)
        XCTAssertTrue(RouterStepsPort.current is SystemRouterSteps)
        XCTAssertTrue(MusicAppPort.current is SystemMusicApp)
        XCTAssertTrue(CountryGeocoderPort.current is LiveCountryGeocoder)
        XCTAssertTrue(BriefingTravelPort.current is LiveBriefingTravel)
        XCTAssertTrue(ReminderPlacePort.current is ReminderPlaceLookupChain)
        XCTAssertTrue(EventKitReminderStore.liveStore is LiveReminderEventStore)
        XCTAssertTrue(DocumentScannerPort.current is DocumentScannerSystem)
        XCTAssertTrue(PriceWatchBackgroundPort.current is PriceWatchBackgroundSystem)

        let host = UIViewController()
        ShareCloserPort.make(host).close()

        _ = VoiceHardwarePort.makeTap()
        _ = VoiceHardwarePort.makeDisruptions()
        _ = VoiceHardwarePort.makeHeadsets()
        XCTAssertEqual(VoiceMicrophonePort.allowed(), AVAudioApplication.shared.recordPermission == .granted)
        _ = MessageSenderPort.compose()
        _ = MessageSenderPort.carrier()

        _ = MediaLibraryReader.authorizationStatus()
        _ = await MediaLibraryReader.requestAuthorization()
        _ = MediaLibraryIndex.playlists()
        _ = MediaLibraryIndex.artists()
        _ = MediaLibraryIndex.albums()
        _ = MediaLibraryIndex.songs()

        _ = await BriefingTravelPort.current.briefingTravel(to: "", departure: Date())
        _ = await ReminderPlacePort.current.locate("")

        _ = await OnDeviceTranslation.supportedCodes()
        _ = await OnDeviceTranslation.status(for: TranslationJob(text: "Hallo", targetCode: "fr"))

        _ = await NotificationTimer.delivery.authorizationStatus()
        _ = try? await NotificationTimer.delivery.deliver(UNNotificationRequest(
            identifier: "gwen.test.timer", content: UNMutableNotificationContent(), trigger: nil))
        #if canImport(AlarmKit)
        _ = AlarmKitTimer.authorizationState()
        #endif

        CameraPresenter.shared.captureOverride = { UIImage() }
        DocumentScannerSystem.isSupportedOverride = false
        let pages = await DocumentScannerSystem.shared.scan()
        XCTAssertEqual(pages?.count, 1)
        DocumentScannerSystem.isSupportedOverride = nil
        CameraPresenter.shared.captureOverride = nil

        let scanning = Task { await DocumentScannerSystem.shared.scan() }
        let deadline = Date().addingTimeInterval(3)
        while !(Presenter.topViewController is VNDocumentCameraViewController), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard let camera = Presenter.topViewController as? VNDocumentCameraViewController else {
            DocumentScannerSystem.shared.documentCameraViewControllerDidCancel(VNDocumentCameraViewController())
            _ = await scanning.value
            throw XCTSkip("Die Scanner-Kamera ließ sich nicht präsentieren")
        }
        DocumentScannerSystem.shared.documentCameraViewControllerDidCancel(camera)
        let cancelled = await scanning.value
        XCTAssertNil(cancelled)
    }
}
#endif
