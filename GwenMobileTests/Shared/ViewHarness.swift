@testable import GwenMobileSystem
@testable import GwenMobileAdapters
@testable import GwenMobileDevice
@testable import GwenMobileFeatureCore
import SwiftUI
import UIKit
import XCTest

@MainActor
private enum ViewHarness {
    static var fallbackWindow: UIWindow?
}

extension XCTestCase {
    @MainActor
    func mountView(_ view: some View, size: CGSize = CGSize(width: 390, height: 900))
        -> UIHostingController<AnyView> {
        let controller = UIHostingController(rootView: AnyView(view))
        controller.view.frame = CGRect(origin: .zero, size: size)
        let window = Presenter.windowRootViewController?.view.window ?? fallbackWindow(size: size)
        if let window {
            window.addSubview(controller.view)
            window.layoutIfNeeded()
        } else {
            controller.view.layoutIfNeeded()
        }
        addTeardownBlock {
            controller.view.removeFromSuperview()
        }
        return controller
    }

    @MainActor
    private func fallbackWindow(size: CGSize) -> UIWindow? {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return nil }
        if let existing = ViewHarness.fallbackWindow, existing.windowScene === scene {
            return existing
        }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.isHidden = false
        ViewHarness.fallbackWindow = window
        return window
    }

    @MainActor
    func settleHosted(_ controller: UIHostingController<some View>, milliseconds: Int = 120) async throws {
        try await Task.sleep(for: .milliseconds(milliseconds))
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
    }

    @MainActor
    func hostWindow(_ view: some View, frame: CGRect = CGRect(x: 0, y: 0, width: 390, height: 900))
        -> UIWindow? {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return nil }
        let window = UIWindow(windowScene: scene)
        window.frame = frame
        window.rootViewController = UIHostingController(rootView: AnyView(view))
        window.makeKeyAndVisible()
        return window
    }

    @MainActor
    func renderView(_ view: some View, width: CGFloat = 300, height: CGFloat? = nil) -> UIImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: width, height: height)
        return renderer.uiImage
    }
}
