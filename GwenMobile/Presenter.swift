import UIKit

enum PresenterError: LocalizedError {
    case noHost

    var errorDescription: String? {
        switch self {
        case .noHost: return L.t("export_unavailable")
        }
    }
}

struct ShareCloseRule: Equatable {
    let activities: Set<UIActivity.ActivityType>

    init(_ activities: Set<UIActivity.ActivityType> = []) {
        self.activities = activities
    }

    var tracksHandover: Bool { !activities.isEmpty }

    func closes(on activityType: UIActivity.ActivityType?) -> Bool {
        guard let activityType else { return false }
        return activities.contains(activityType)
    }
}

final class ShareItemSource: NSObject, UIActivityItemSource {
    private let url: URL
    private let onActivity: @Sendable (UIActivity.ActivityType?) -> Void

    init(url: URL, onActivity: @escaping @Sendable (UIActivity.ActivityType?) -> Void) {
        self.url = url
        self.onActivity = onActivity
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        url
    }

    func activityViewController(_ activityViewController: UIActivityViewController,
                                itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        onActivity(activityType)
        return url
    }
}

@MainActor
final class ShareChainCloser {
    private weak var host: UIViewController?

    init(host: UIViewController) {
        self.host = host
    }

    func close() {
        guard let host, let top = host.presentedViewController, !top.isBeingDismissed else { return }
        Task { @MainActor in
            host.dismiss(animated: true)
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

    static func share(url: URL, closesOn activities: Set<UIActivity.ActivityType> = []) throws {
        guard let host = topViewController else { throw PresenterError.noHost }
        let rule = ShareCloseRule(activities)
        let closer = ShareChainCloser(host: host)
        let sheet = UIActivityViewController(activityItems: itemsForShare(url: url, rule: rule, closer: closer),
                                             applicationActivities: nil)
        sheet.excludedActivityTypes = [.addToReadingList]
        sheet.completionWithItemsHandler = { _, _, _, _ in
            Task { @MainActor in closer.close() }
        }
        sheet.popoverPresentationController?.sourceView = host.view
        sheet.popoverPresentationController?.sourceRect =
            CGRect(x: host.view.bounds.midX, y: host.view.bounds.midY, width: 0, height: 0)
        host.present(sheet, animated: true)
    }

    private static func itemsForShare(url: URL, rule: ShareCloseRule,
                                      closer: ShareChainCloser) -> [Any] {
        guard rule.tracksHandover else { return [url] }
        return [ShareItemSource(url: url) { activity in
            guard rule.closes(on: activity) else { return }
            Task { @MainActor in closer.close() }
        }]
    }
}
