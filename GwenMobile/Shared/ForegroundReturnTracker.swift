import UIKit

@MainActor
protocol ForegroundReturnTracking: AnyObject {
    func start(onReturn: @escaping @MainActor () -> Void)
    func stop()
}

private final class ForegroundObservers {
    var tokens: [NSObjectProtocol] = []

    deinit {
        let center = NotificationCenter.default
        for token in tokens {
            center.removeObserver(token)
        }
    }
}

@MainActor
final class AppForegroundReturnTracker: ForegroundReturnTracking {
    private let observers = ForegroundObservers()
    private var onReturn: (@MainActor () -> Void)?
    private var leftForeground = false

    func start(onReturn: @escaping @MainActor () -> Void) {
        guard observers.tokens.isEmpty else { return }
        self.onReturn = onReturn
        let center = NotificationCenter.default
        observers.tokens.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                                   object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.leftForeground = true }
        })
        observers.tokens.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                                   object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reportReturn() }
        })
    }

    func stop() {
        let center = NotificationCenter.default
        observers.tokens.forEach { center.removeObserver($0) }
        observers.tokens = []
        onReturn = nil
        leftForeground = false
    }

    private func reportReturn() {
        guard leftForeground else { return }
        leftForeground = false
        onReturn?()
    }
}
