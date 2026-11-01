@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import AlarmKit
import UserNotifications
import XCTest
import GwenMobileKit

@MainActor
final class TimerSettingGapTests: GwenTestCase {
    private func resetStatics() {
        NotificationTimer.delivery.authorizationStatus = {
            await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        }
        NotificationTimer.requestPermission = {
            (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
        NotificationTimer.delivery.deliverOverride = {
            try await UNUserNotificationCenter.current().add($0)
        }
        #if !targetEnvironment(macCatalyst)
        AlarmKitTimer.authorizationState = { AlarmManager.shared.authorizationState }
        AlarmKitTimer.requestPermission = {
            (try? await AlarmManager.shared.requestAuthorization()) ?? .denied
        }
        AlarmKitTimer.scheduleTimer = { duration, attributes in
            let alarm = try await AlarmManager.shared.schedule(id: UUID(),
                                                               configuration: .timer(duration: duration,
                                                                                     attributes: attributes))
            return alarm.id
        }
        #endif
    }

    func testTheNotificationTimerBranches() async {
        resetStatics()
        defer { resetStatics() }
        let request = TimerRequest(minutes: 1, seconds: nil, title: "Tee")
        NotificationTimer.delivery.authorizationStatus = { .authorized }
        NotificationTimer.delivery.deliverOverride = { _ in }
        let authorized = await NotificationTimer.set(request)
        if case .set(let duration, let way) = authorized {
            XCTAssertEqual(duration, request.duration)
            XCTAssertEqual(way, "meldung")
        } else {
            XCTFail("erwartet gesetzt: \(authorized)")
        }
        NotificationTimer.delivery.authorizationStatus = { .provisional }
        _ = await NotificationTimer.set(request)
        NotificationTimer.delivery.authorizationStatus = { .notDetermined }
        NotificationTimer.requestPermission = { true }
        _ = await NotificationTimer.set(request)
        NotificationTimer.requestPermission = { false }
        let denied = await NotificationTimer.set(request)
        XCTAssertEqual(denied, .denied)
        NotificationTimer.delivery.authorizationStatus = { .denied }
        let refused = await NotificationTimer.set(request)
        XCTAssertEqual(refused, .denied)
        NotificationTimer.delivery.authorizationStatus = { .authorized }
        NotificationTimer.delivery.deliverOverride = { _ in throw APIError(message: "kaputt") }
        if case .failed = await NotificationTimer.set(request) {
        } else {
            XCTFail("erwartet Fehler")
        }
        _ = await NotificationTimer.delivery.authorizationStatus()
    }

    #if !targetEnvironment(macCatalyst)
    func testTheAlarmKitTimerBranches() async {
        resetStatics()
        defer { resetStatics() }
        let request = TimerRequest(minutes: 2, seconds: nil, title: "Tee")
        AlarmKitTimer.authorizationState = { .authorized }
        AlarmKitTimer.scheduleTimer = { _, _ in UUID() }
        if case .set(let duration, let way) = await AlarmKitTimer.set(request) {
            XCTAssertEqual(duration, request.duration)
            XCTAssertEqual(way, "alarmkit")
        } else {
            XCTFail("erwartet gesetzt")
        }
        AlarmKitTimer.authorizationState = { .notDetermined }
        AlarmKitTimer.requestPermission = { .authorized }
        _ = await AlarmKitTimer.set(request)
        AlarmKitTimer.requestPermission = { .denied }
        let denied = await AlarmKitTimer.set(request)
        XCTAssertEqual(denied, .denied)
        AlarmKitTimer.authorizationState = { .denied }
        _ = await AlarmKitTimer.set(request)
        AlarmKitTimer.authorizationState = { .authorized }
        AlarmKitTimer.scheduleTimer = { _, _ in throw APIError(message: "kaputt") }
        if case .failed = await AlarmKitTimer.set(request) {
        } else {
            XCTFail("erwartet Fehler")
        }
        _ = AlarmKitTimer.authorizationState()
        if #available(iOS 26.1, *) {
            _ = try? await AlarmKitTimer.scheduleTimer(request.duration,
                                                       AlarmAttributes<AlarmKitTimer.Metadata>(
                                                        presentation: AlarmPresentation(alert: AlarmPresentation.Alert(
                                                            title: LocalizedStringResource(stringLiteral: "Tee"))),
                                                        metadata: nil, tintColor: .orange))
        }
    }

    func testTheSystemTimerSetterRuns() async {
        resetStatics()
        defer { resetStatics() }
        let request = TimerRequest(minutes: 1, seconds: nil, title: "Tee")
        AlarmKitTimer.authorizationState = { .denied }
        let denied = await SystemTimerSetter().set(request)
        XCTAssertEqual(denied, .denied)
    }
    #endif
}
