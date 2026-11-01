import GwenMobileKit
import Foundation
import UIKit

enum LocalRuntime {
    @MainActor private static var installed = false

    @MainActor static func install() {
        guard !installed else { return }
        installed = true
        HTTP.localResponder = { request in
            await LocalOpenAI.response(for: request)
        }
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                           object: nil, queue: .main) { _ in
            Task { await LocalEngine.shared.unloadIfIdle() }
        }
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                           object: nil, queue: .main) { _ in
            Task { await LocalEngine.shared.unloadIfIdle() }
        }
    }

    nonisolated static func isLocal(_ request: URLRequest) -> Bool {
        LocalEndpoint.isLocal(request)
    }

    nonisolated static func streamLines(_ request: URLRequest) -> AsyncThrowingStream<String, Error> {
        LocalOpenAI.streamLines(for: request)
    }
}
