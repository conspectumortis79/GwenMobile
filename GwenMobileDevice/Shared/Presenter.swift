@testable import GwenMobileFeatureCore
import GwenMobileKit
import UIKit

enum PresenterError: LocalizedError {
    case noHost

    var errorDescription: String? {
        switch self {
        case .noHost: return L.t("export_unavailable")
        }
    }
}

@MainActor
enum Presenter {
    #if DEBUG
    static var hostOverride: UIViewController?
    static var shareOverride: (([URL], ShareHandoverPolicy) throws -> Void)?
    static var lastShareSession: ShareSession?
    #endif

    static var windowRootViewController: UIViewController? {
        #if DEBUG
        if let hostOverride { return hostOverride }
        #endif
        return UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })?
            .windows.first(where: { $0.isKeyWindow })?.rootViewController
    }

    static var topViewController: UIViewController? {
        guard var top = windowRootViewController else { return nil }
        while let presented = top.presentedViewController { top = presented }
        return top
    }

    static func present(_ controller: UIViewController, from host: UIViewController) {
        controller.popoverPresentationController?.sourceView = host.view
        controller.popoverPresentationController?.sourceRect =
            CGRect(x: host.view.bounds.midX, y: host.view.bounds.midY, width: 0, height: 0)
        host.present(controller, animated: true)
    }

    @discardableResult
    static func presentIfPossible(_ controller: UIViewController) -> Bool {
        guard let host = topViewController else { return false }
        present(controller, from: host)
        return true
    }

    static func share(url: URL, policy: ShareHandoverPolicy = ShareHandoverPolicy()) throws {
        try share(urls: [url], policy: policy)
    }

    static func share(urls: [URL], policy: ShareHandoverPolicy = ShareHandoverPolicy()) throws {
        #if DEBUG
        if let shareOverride {
            try shareOverride(urls, policy)
            return
        }
        #endif
        try performShare(urls: urls, policy: policy)
    }

    private static func performShare(urls: [URL], policy: ShareHandoverPolicy) throws {
        guard let host = topViewController, !urls.isEmpty else { throw PresenterError.noHost }
        let session = ShareSession(closer: ShareCloserPort.make(host), policy: policy)
        #if DEBUG
        lastShareSession = session
        #endif
        let sheet = UIActivityViewController(activityItems: urls.map { session.itemSource(for: $0) },
                                             applicationActivities: nil)
        sheet.excludedActivityTypes = [.addToReadingList]
        sheet.completionWithItemsHandler = { _, _, _, _ in
            Task { @MainActor in session.noteSystemCompletion() }
        }
        present(sheet, from: host)
    }
}
