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
enum ShareCloserPort {
    nonisolated(unsafe) static var make: @MainActor (UIViewController) -> any SharePresentationClosing = { _ in
        StubShareCloser()
    }
}

@MainActor
final class StubShareCloser: SharePresentationClosing {
    func close() {}
}

final class ShareItemSource: NSObject, UIActivityItemSource {
    private let url: URL
    private let onActivity: @Sendable (UIActivity.ActivityType?) -> Void

    init(url: URL, onActivity: @escaping @Sendable (UIActivity.ActivityType?) -> Void) {
        self.url = url
        self.onActivity = onActivity
    }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any { url }

    func activityViewController(_ controller: UIActivityViewController,
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

    func itemSource(for url: URL) -> UIActivityItemSource {
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
