import GwenMobileKit
import Foundation
import UserNotifications

enum MemoryNotifier {
    @MainActor
    static var delivery = NotificationDelivery()

    @MainActor
    static func prepare() {
        NotificationPermission.request(reporting: "GEDÄCHTNIS mitteilung_erlaubt")
    }

    @MainActor
    static func notify(_ entry: MemoryEntry) async -> Bool {
        let status = await delivery.authorizationStatus()
        guard status == .authorized || status == .provisional else {
            flowMark("GEDÄCHTNIS mitteilung nicht_erlaubt status=\(status.rawValue)")
            return false
        }
        let content = UNMutableNotificationContent()
        content.title = L.t("memory_notify_title")
        content.body = TextLine.oneLine(entry.text, limit: 220)
        content.sound = .default
        let request = UNNotificationRequest(identifier: "gwen.memory." + entry.shortKey,
                                            content: content, trigger: nil)
        do {
            try await delivery.deliver(request)
            return true
        } catch {
            flowMark("GEDÄCHTNIS mitteilung fehler=\(error.localizedDescription)")
            return false
        }
    }
}
