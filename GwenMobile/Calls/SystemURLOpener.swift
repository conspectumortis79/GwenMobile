import Foundation
import UIKit

@MainActor
struct SystemURLOpener: URLOpening {
    func open(_ url: URL) async -> Bool {
        await UIApplication.shared.open(url)
    }
}
