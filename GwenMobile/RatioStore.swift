import CoreGraphics
import Foundation

final class RatioStore: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: CGFloat] = [:]

    func value(for file: String) -> CGFloat? {
        lock.lock()
        defer { lock.unlock() }
        return values[file]
    }

    func setValue(_ ratio: CGFloat, for file: String) {
        lock.lock()
        defer { lock.unlock() }
        values[file] = ratio
    }

    func drop(_ file: String) {
        lock.lock()
        defer { lock.unlock() }
        values[file] = nil
    }
}
