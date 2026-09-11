import UIKit

@MainActor
protocol ForegroundReturnTracking: AnyObject {
    func start(onReturn: @escaping @MainActor () -> Void)
    func stop()
}

@MainActor
final class AppForegroundReturnTracker: ForegroundReturnTracking {
    private var tokens: [NSObjectProtocol] = []
    private var onReturn: (@MainActor () -> Void)?
    private var leftForeground = false

    func start(onReturn: @escaping @MainActor () -> Void) {
        guard tokens.isEmpty else { return }
        self.onReturn = onReturn
        let center = NotificationCenter.default
        tokens.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                         object: nil, queue: .main) { _ in
            Task { @MainActor [weak self] in self?.leftForeground = true }
        })
        tokens.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                         object: nil, queue: .main) { _ in
            Task { @MainActor [weak self] in self?.reportReturn() }
        })
    }

    func stop() {
        let center = NotificationCenter.default
        tokens.forEach { center.removeObserver($0) }
        tokens = []
        onReturn = nil
        leftForeground = false
    }

    private func reportReturn() {
        guard leftForeground else { return }
        leftForeground = false
        onReturn?()
    }
}
