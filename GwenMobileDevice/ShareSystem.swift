@testable import GwenMobileFeatureCore
import UIKit

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

@MainActor
enum ShareSystem {
    static func install() {
        ShareCloserPort.make = { ShareChainCloser(host: $0) }
    }
}
