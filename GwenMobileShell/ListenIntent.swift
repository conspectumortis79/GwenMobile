import AppIntents
import GwenMobileFeatureCore

struct ListenIntent: AppIntent {
    static let title: LocalizedStringResource = "Listen"
    static let description = IntentDescription("Opens GwenMobile and starts listening for your request.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ListenRequests.shared.ask(from: "siri")
        return .result()
    }
}

struct GwenShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ListenIntent(),
                    phrases: ["\(.applicationName)", "\(.applicationName) listen"],
                    shortTitle: "Listen",
                    systemImageName: "mic.fill")
    }
}
