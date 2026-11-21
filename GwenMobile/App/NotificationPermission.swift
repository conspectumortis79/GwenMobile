import GwenMobileKit
import UserNotifications

@MainActor
enum NotificationPermission {
    #if DEBUG
    nonisolated(unsafe) static var askOverride: (@MainActor () async throws -> Bool)?
    #endif

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
            #if DEBUG
            if let askOverride { return try await askOverride() }
            #endif
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }
}
