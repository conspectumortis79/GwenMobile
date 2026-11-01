@testable import GwenMobileFeatureCore
import GwenMobileKit
#if targetEnvironment(macCatalyst)
import SwiftUI

@MainActor
enum MacPresence {
    static func quit() {
        AppSettings.flushKeySave()
        flowLog.info("MAC beendet durch benutzer")
        exit(0)
    }
}

struct MacWindowCommands: Commands {
    private let onQuit: () -> Void

    init(onQuit: @escaping () -> Void) {
        self.onQuit = onQuit
    }

    var body: some Commands {
        CommandGroup(replacing: .appTermination) {
            Button(L.t("mac_quit"), action: onQuit)
                .keyboardShortcut("q", modifiers: .command)
        }
    }
}
#endif
