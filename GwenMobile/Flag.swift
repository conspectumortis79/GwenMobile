import Foundation

final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool

    init(_ initial: Bool) { value = initial }

    func set(_ v: Bool) {
        lock.lock(); defer { lock.unlock() }
        value = v
    }

    func exchange(_ v: Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let old = value
        value = v
        return old
    }
}
