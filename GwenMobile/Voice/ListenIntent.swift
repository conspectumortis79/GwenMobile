import GwenMobileKit
import AppIntents
import Foundation

@MainActor
final class ListenRequests: ObservableObject {
    static let shared = ListenRequests()

    @Published var token = 0

    func ask(from source: String) {
        flowMark("LISTEN anfrage quelle=\(source)")
        token += 1
    }
}

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
