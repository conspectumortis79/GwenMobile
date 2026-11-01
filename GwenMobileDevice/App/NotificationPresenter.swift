@testable import GwenMobileFeatureCore
import GwenMobileKit
import UserNotifications

private final class NotificationCompletion: @unchecked Sendable {
    private let run: () -> Void

    init(_ run: @escaping () -> Void) {
        self.run = run
    }

    func call() { run() }
}

final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let day = NotificationRoute.briefingDay(in: info)
        flowMark("BRIEFING tap hauptfaden=\(Thread.isMainThread)")
        let completion = NotificationCompletion(completionHandler)
        DispatchQueue.main.async {
            completion.call()
            guard let day else { return }
            DispatchQueue.main.async {
                BriefingOpenRequests.shared.ask(day: day)
            }
        }
    }
}
