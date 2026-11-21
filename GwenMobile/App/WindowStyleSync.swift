import UIKit

@MainActor
enum WindowStyleSync {
    static func apply(_ style: UIUserInterfaceStyle) {
        apply(style, to: sceneWindows())
    }

    static func apply(_ style: UIUserInterfaceStyle, to windows: [UIWindow]) {
        for window in windows {
            window.overrideUserInterfaceStyle = style
        }
    }

    static func sceneWindows() -> [UIWindow] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
    }
}
