import GwenMobileKit
import UIKit

enum ViewerArrowKeys {
    nonisolated static var enabledOnThisPlatform: Bool { ProcessInfo.processInfo.isMacCatalystApp }

    @MainActor static func commands(back: Selector, forward: Selector) -> [UIKeyCommand] {
        [command(UIKeyCommand.inputLeftArrow, back, L.t("previous_picture")),
         command(UIKeyCommand.inputRightArrow, forward, L.t("next_picture"))]
    }

    @MainActor private static func command(_ input: String, _ action: Selector,
                                           _ title: String) -> UIKeyCommand {
        let command = UIKeyCommand(input: input, modifierFlags: [], action: action)
        command.discoverabilityTitle = title
        command.wantsPriorityOverSystemBehavior = true
        return command
    }
}
