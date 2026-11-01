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
}
