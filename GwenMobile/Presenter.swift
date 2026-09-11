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
    static var topViewController: UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        return top
    }

    static func share(url: URL) throws {
        try share(items: [url])
    }

    static func share(items: [Any]) throws {
        guard let host = topViewController else { throw PresenterError.noHost }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        sheet.excludedActivityTypes = [.addToReadingList]
        sheet.popoverPresentationController?.sourceView = host.view
        sheet.popoverPresentationController?.sourceRect =
            CGRect(x: host.view.bounds.midX, y: host.view.bounds.midY, width: 0, height: 0)
        host.present(sheet, animated: true)
    }
}
