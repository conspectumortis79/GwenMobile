import GwenMobileKit
import Foundation
import UIKit

enum LocalRuntime {
    @MainActor private static var observers: LocalRuntimeObservers?

    @MainActor static func install() {
        guard observers == nil else { return }
        HTTP.localResponder = { request in
            await LocalOpenAI.response(for: request)
        }
        observers = LocalRuntimeObservers()
    }

    #if DEBUG
    @MainActor static var observerCount: Int { observers?.count ?? 0 }

    @MainActor static func stop() {
        observers = nil
    }
    #endif

    nonisolated static func isLocal(_ request: URLRequest) -> Bool {
        LocalEndpoint.isLocal(request)
    }

    nonisolated static func streamLines(_ request: URLRequest) -> AsyncThrowingStream<String, Error> {
        LocalOpenAI.streamLines(for: request)
    }
}

private final class LocalRuntimeObservers {
    private let tokens: [NSObjectProtocol]

    init(center: NotificationCenter = .default) {
        tokens = [
            center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                               object: nil, queue: .main) { _ in
                Task { await LocalEngine.shared.unloadIfIdle() }
            },
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                               object: nil, queue: .main) { _ in
                Task { await LocalEngine.shared.unloadIfIdle() }
            },
        ]
    }

    #if DEBUG
    var count: Int { tokens.count }
    #endif

    deinit {
        let center = NotificationCenter.default
        for token in tokens { center.removeObserver(token) }
    }
}
