import GwenMobileKit
import UserNotifications

@MainActor
struct NotificationDelivery {
    var authorizationStatus: () async -> UNAuthorizationStatus = {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    var deliverOverride: (@MainActor (UNNotificationRequest) async throws -> Void)?

    func deliver(_ request: UNNotificationRequest) async throws {
        if let deliverOverride {
            try await deliverOverride(request)
            return
        }
        try await UNUserNotificationCenter.current().add(request)
    }

    func deliver(title: String, body: String, identifier: String,
                 userInfo: [String: String] = [:], label: String) async -> Bool {
        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional else {
            flowMark("\(label) mitteilung nicht_erlaubt status=\(status.rawValue)")
            return false
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        do {
            try await deliver(request)
            return true
        } catch {
            flowMark("\(label) mitteilung fehler=\(error.localizedDescription)")
            return false
        }
    }
}
