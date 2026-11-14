import GwenMobileKit
import Foundation

enum MemoryNotifier {
    @MainActor
    static var delivery = NotificationDelivery()

    @MainActor
    static func prepare() {
        NotificationPermission.request(reporting: "GEDÄCHTNIS mitteilung_erlaubt")
    }

    @MainActor
    static func notify(_ entry: MemoryEntry) async -> Bool {
        await delivery.deliver(title: L.t("memory_notify_title"),
                               body: TextLine.oneLine(entry.text, limit: 220),
                               identifier: "gwen.memory." + entry.shortKey,
                               label: "GEDÄCHTNIS")
    }
}
