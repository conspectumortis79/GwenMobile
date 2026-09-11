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

    private(set) static weak var activeShareSheet: UIActivityViewController?

    static func share(url: URL) throws {
        try share(items: [url])
    }

    static func share(items: [Any]) throws {
        guard let host = topViewController else { throw PresenterError.noHost }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        sheet.excludedActivityTypes = [.addToReadingList]
        sheet.completionWithItemsHandler = { [weak host] _, completed, _, _ in
            guard completed, host?.presentedViewController != nil else { return }
            host?.dismiss(animated: true)
        }
        sheet.popoverPresentationController?.sourceView = host.view
        sheet.popoverPresentationController?.sourceRect =
            CGRect(x: host.view.bounds.midX, y: host.view.bounds.midY, width: 0, height: 0)
        activeShareSheet = sheet
        host.present(sheet, animated: true)
    }
}
