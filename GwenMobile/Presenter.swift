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
    static var windowRootViewController: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })?
            .windows.first(where: { $0.isKeyWindow })?.rootViewController
    }

    static var topViewController: UIViewController? {
        guard var top = windowRootViewController else { return nil }
        while let presented = top.presentedViewController { top = presented }
        return top
    }

    static func share(url: URL, policy: ShareHandoverPolicy = ShareHandoverPolicy()) throws {
        guard let host = topViewController else { throw PresenterError.noHost }
        let session = ShareSession(closer: ShareChainCloser(host: host), policy: policy)
        let sheet = UIActivityViewController(activityItems: [session.itemSource(for: url)],
                                             applicationActivities: nil)
        sheet.excludedActivityTypes = [.addToReadingList]
        sheet.completionWithItemsHandler = { _, _, _, _ in
            Task { @MainActor in session.noteSystemCompletion() }
        }
        sheet.popoverPresentationController?.sourceView = host.view
        sheet.popoverPresentationController?.sourceRect =
            CGRect(x: host.view.bounds.midX, y: host.view.bounds.midY, width: 0, height: 0)
        host.present(sheet, animated: true)
    }
}
