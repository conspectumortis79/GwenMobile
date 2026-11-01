import UIKit

@MainActor
enum URLOpenSpy {
    nonisolated(unsafe) private static var original: Method?
    nonisolated(unsafe) private static var replacement: Method?
    nonisolated(unsafe) static var opened: [URL] = []

    static func install() {
        guard original == nil else { return }
        original = class_getInstanceMethod(UIApplication.self,
                                           NSSelectorFromString("openURL:options:completionHandler:"))
        replacement = class_getInstanceMethod(UIApplication.self,
                                              #selector(UIApplication.gapOpenURL(_:options:completionHandler:)))
        if let original, let replacement {
            method_exchangeImplementations(original, replacement)
        }
    }

    static func uninstall() {
        if let original, let replacement {
            method_exchangeImplementations(original, replacement)
        }
        original = nil
        replacement = nil
    }
}

private extension UIApplication {
    @objc func gapOpenURL(_ url: URL,
                                      options: [UIApplication.OpenExternalURLOptionsKey: Any],
                                      completionHandler: ((Bool) -> Void)?) {
        URLOpenSpy.opened.append(url)
        completionHandler?(false)
    }
}
