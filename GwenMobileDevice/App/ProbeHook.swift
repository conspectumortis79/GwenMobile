import GwenMobileKit
#if DEBUG
import SwiftUI

@MainActor
enum ProbeHook {
    static var start: ((ChatView) -> Void)?
    static var appear: ((ChatView) -> Void)?
    static var dispatch: ((ChatView, String) -> Void)?
    static var attachScrollProxy: ((ChatView, ScrollViewProxy) -> Void)?
    static var installTouchLog: (() -> Void)?
    private static var launchDispatched = false

    static func launchName(arguments: [String] = CommandLine.arguments) -> String? {
        guard !launchDispatched,
              let index = arguments.firstIndex(of: "-gwenflowtest"), index + 1 < arguments.count else {
            return nil
        }
        launchDispatched = true
        return arguments[index + 1]
    }
}
#endif
