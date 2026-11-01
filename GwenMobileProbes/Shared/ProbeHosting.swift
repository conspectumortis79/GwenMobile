@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
#if DEBUG
import GwenMobileKit
import SwiftUI
import UIKit

@MainActor
enum ProbeHosting {
    static func host<Content: View>(_ content: Content, frame: CGRect? = nil) -> UIWindow? {
        guard let main = Presenter.windowRootViewController?.view?.window,
              let scene = main.windowScene else { return nil }
        let host = UIHostingController(rootView: content)
        let window = UIWindow(windowScene: scene)
        window.frame = frame ?? main.bounds
        window.rootViewController = host
        window.backgroundColor = .systemBackground
        window.makeKeyAndVisible()
        return window
    }

    static func close(_ window: UIWindow) {
        window.isHidden = true
        window.rootViewController = nil
    }

    static func waitForMainWindow(seconds: Double = 3) async -> UIWindow? {
        var window: UIWindow?
        _ = await ProbeWait.until(seconds) {
            if let main = Presenter.windowRootViewController?.view?.window, main.isKeyWindow {
                window = main
                return true
            }
            return false
        }
        return window
    }

    static func snapshot(_ window: UIWindow, _ file: String) -> String {
        ViewerProbe.snapshot(window, named: file)
    }

    static func settledSnapshot(_ window: UIWindow, _ file: String, rounds: Int = 20) async -> String {
        var previous: Data?
        for _ in 0..<rounds {
            let name = snapshot(window, file)
            let data = try? Data(contentsOf: StoragePaths().documents.appendingPathComponent(name))
            if let data, data == previous { return name }
            previous = data
            try? await Task.sleep(for: .milliseconds(150))
        }
        return file
    }
}
#endif
