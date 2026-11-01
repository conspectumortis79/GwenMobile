@testable import GwenMobileDevice
import UIKit
import XCTest

@MainActor
extension XCTestCase {
    func dismissPresentedSheets() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        for scene in UIApplication.shared.connectedScenes {
            guard let windows = (scene as? UIWindowScene)?.windows else { continue }
            for window in windows {
                window.endEditing(true)
                var chain: [UIViewController] = []
                var current = window.rootViewController
                while let presented = current?.presentedViewController {
                    chain.append(presented)
                    current = presented
                }
                for controller in chain.reversed() {
                    controller.dismiss(animated: false)
                    RunLoop.current.run(until: Date().addingTimeInterval(0.02))
                }
            }
        }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        CameraPresenter.shared.onImage = nil
        DocumentPresenter.shared.onURLs = nil
    }
}
