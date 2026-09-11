import UIKit

struct ShareHandoverPolicy: Equatable {
    let closesOnHandover: Set<UIActivity.ActivityType>

    init(closesOnHandover: Set<UIActivity.ActivityType> = [.airDrop]) {
        self.closesOnHandover = closesOnHandover
    }

    func closesTheSheet(on activityType: UIActivity.ActivityType?) -> Bool {
        guard let activityType else { return false }
        return closesOnHandover.contains(activityType)
    }
}

@MainActor
protocol SharePresentationClosing: AnyObject {
    func close()
}

@MainActor
final class ShareChainCloser: SharePresentationClosing {
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
final class ShareSession {
    private let closer: SharePresentationClosing
    private let foreground: ForegroundReturnTracking
    private let policy: ShareHandoverPolicy
    private var handedOver = false
    private var closed = false

    init(closer: SharePresentationClosing,
         foreground: ForegroundReturnTracking = AppForegroundReturnTracker(),
         policy: ShareHandoverPolicy = ShareHandoverPolicy()) {
        self.closer = closer
        self.foreground = foreground
        self.policy = policy
        foreground.start { [weak self] in
            self?.noteReturnedToForeground()
        }
    }

    func itemSource(for url: URL) -> ShareItemSource {
        ShareItemSource(url: url) { activity in
            Task { @MainActor in self.noteHandover(activity) }
        }
    }

    func noteHandover(_ activityType: UIActivity.ActivityType?) {
        guard !closed, let activityType else { return }
        handedOver = true
        guard policy.closesTheSheet(on: activityType) else { return }
        closeNow()
    }

    func noteSystemCompletion() {
        guard !closed else { return }
        closeNow()
    }

    func noteReturnedToForeground() {
        guard !closed, handedOver else { return }
        closeNow()
    }

    private func closeNow() {
        closed = true
        foreground.stop()
        closer.close()
    }
}
