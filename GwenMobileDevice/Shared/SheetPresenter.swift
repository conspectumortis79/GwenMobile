import UIKit

@MainActor
final class SheetPresenter: NSObject, UIAdaptivePresentationControllerDelegate {
    private(set) var presented: UIViewController?
    private var onDismiss: (() -> Void)?

    var isFree: Bool { presented == nil }

    @discardableResult
    func show(_ controller: UIViewController, onDismiss: (() -> Void)? = nil) -> Bool {
        guard presented == nil, Presenter.presentIfPossible(controller) else { return false }
        controller.presentationController?.delegate = self
        presented = controller
        self.onDismiss = onDismiss
        return true
    }

    @discardableResult
    func release() -> UIViewController? {
        let released = presented
        released?.presentationController?.delegate = nil
        presented = nil
        onDismiss = nil
        return released
    }

    func dismiss(animated: Bool) {
        release()?.dismiss(animated: animated)
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard presented != nil else { return }
        presented = nil
        let callback = onDismiss
        onDismiss = nil
        callback?()
    }
}
