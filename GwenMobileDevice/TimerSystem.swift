@testable import GwenMobileFeatureCore
import GwenMobileKit
import Foundation
import UserNotifications

#if canImport(AlarmKit) && !targetEnvironment(macCatalyst)
import AlarmKit
#endif

@MainActor
struct SystemTimerSetter: TimerSetting {
    func set(_ request: TimerRequest) async -> TimerSettingResult {
        #if canImport(AlarmKit) && !targetEnvironment(macCatalyst)
        return await AlarmKitTimer.set(request)
        #else
        return await NotificationTimer.set(request)
        #endif
    }
}

@MainActor
enum NotificationTimer {
    static var delivery = NotificationDelivery()

    nonisolated(unsafe) static var requestPermission: @MainActor () async -> Bool = {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func set(_ request: TimerRequest) async -> TimerSettingResult {
        let status = await delivery.authorizationStatus()
        var allowed = status == .authorized || status == .provisional
        if status == .notDetermined {
            allowed = await requestPermission()
        }
        guard allowed else { return .denied }
        let content = UNMutableNotificationContent()
        content.title = TimerAnswer.title(request)
        content.sound = .default
        let identifier = "gwen.timer." + UUID().uuidString
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, request.duration), repeats: false)
        do {
            try await delivery.deliver(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            return .set(duration: request.duration, way: "meldung")
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

#if canImport(AlarmKit) && !targetEnvironment(macCatalyst)
@MainActor
enum AlarmKitTimer {
    struct Metadata: AlarmMetadata, Sendable {}

    nonisolated(unsafe) static var authorizationState: @MainActor () -> AlarmManager.AuthorizationState = {
        AlarmManager.shared.authorizationState
    }

    nonisolated(unsafe) static var requestPermission: @MainActor () async -> AlarmManager.AuthorizationState = {
        (try? await AlarmManager.shared.requestAuthorization()) ?? .denied
    }

    nonisolated(unsafe) static var scheduleTimer: @MainActor (TimeInterval, AlarmAttributes<Metadata>) async throws -> UUID = {
        duration, attributes in
        let alarm = try await AlarmManager.shared.schedule(id: UUID(),
                                                           configuration: .timer(duration: duration,
                                                                                 attributes: attributes))
        return alarm.id
    }

    static func set(_ request: TimerRequest) async -> TimerSettingResult {
        var state = authorizationState()
        if state == .notDetermined {
            state = await requestPermission()
        }
        guard state == .authorized else { return .denied }
        let title = LocalizedStringResource(stringLiteral: TimerAnswer.title(request))
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: title)
        } else {
            let stop = AlarmButton(text: LocalizedStringResource(stringLiteral: L.t("timer_stop")),
                                   textColor: .white, systemImageName: "stop.fill")
            alert = AlarmPresentation.Alert(title: title, stopButton: stop)
        }
        let presentation = AlarmPresentation(alert: alert,
                                             countdown: AlarmPresentation.Countdown(title: title))
        let attributes = AlarmAttributes<Metadata>(presentation: presentation, metadata: nil, tintColor: .orange)
        do {
            _ = try await scheduleTimer(request.duration, attributes)
            return .set(duration: request.duration, way: "alarmkit")
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
#endif
