import GwenMobileKit
import UserNotifications

@MainActor
enum NotificationPermission {
    nonisolated(unsafe) static var askOverride: (@MainActor () async throws -> Bool)?

    static func request(reporting line: String) {
        request(reporting: line, ask: { await systemAsk() })
    }

    static func request(reporting line: String,
                        ask: @escaping @MainActor () async -> Bool,
                        report: @escaping @MainActor (String) -> Void = { flowMark($0) }) {
        Task {
            let granted = await ask()
            report("\(line)=\(granted)")
        }
    }

    private static func systemAsk() async -> Bool {
        do {
            if let askOverride { return try await askOverride() }
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }
}
