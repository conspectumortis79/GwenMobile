import Foundation
import os

public final class FailureReporter: @unchecked Sendable {
    public let label: String
    private let lock = NSLock()
    private var handler: (@Sendable (String) -> Void)?

    public init(label: String) {
        self.label = label
    }

    public func report(to handler: @escaping @Sendable (String) -> Void) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    public func note(_ message: String) {
        flowLog.error("\(self.label, privacy: .public) \(message, privacy: .public)")
        lock.lock()
        let handler = handler
        lock.unlock()
        handler?(message)
    }
}

public protocol FailureReporting: AnyObject {
    var failures: FailureReporter { get }
}

public extension FailureReporting {
    func reportFailures(_ handler: @escaping @Sendable (String) -> Void) {
        failures.report(to: handler)
    }
}
