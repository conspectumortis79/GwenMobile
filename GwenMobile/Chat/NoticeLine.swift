import GwenMobileKit
import Foundation

@MainActor
final class NoticeLine: TimedFlag<String?> {
    static let defaultLifetime: Duration = .seconds(4)

    var text: String? { value }

    init(lifetime: Duration = NoticeLine.defaultLifetime) {
        super.init(nil, resetTo: nil, after: lifetime)
    }

    func show(_ message: String) {
        set(message)
    }
}
