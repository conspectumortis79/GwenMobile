import GwenMobileKit
import Foundation
import os

private let shieldLog = Logger(subsystem: "com.mortis.gwenmobile", category: "assertion-shield")

struct AssertionFailure: Sendable {
    let site: String
    let file: String
    let line: Int
    let message: String

    var reason: String { "\(site) \(file):\(line) \(message)" }

    func raisedIn(_ expected: String) -> Bool {
        file == expected || (file as NSString).lastPathComponent == expected
    }

    static func method(_ selector: Selector, object: Any?, file: String?, lineNumber: Int, description: String?) -> AssertionFailure {
        let owner = object.map { String(describing: type(of: $0)) } ?? "unknown"
        return AssertionFailure(site: "-[\(owner) \(selector)]",
                                file: file ?? "",
                                line: lineNumber,
                                message: description ?? "")
    }

    static func function(_ name: String?, file: String?, lineNumber: Int, description: String?) -> AssertionFailure {
        AssertionFailure(site: name ?? "",
                         file: file ?? "",
                         line: lineNumber,
                         message: description ?? "")
    }
}

extension NSException {
    convenience init(assertion: AssertionFailure) {
        self.init(name: .internalInconsistencyException, reason: assertion.reason, userInfo: nil)
    }
}

protocol AssertionTolerance: Sendable {
    func tolerates(_ failure: AssertionFailure) -> Bool
}

struct MissingNonAcceleratedScrollDeltaTolerance: AssertionTolerance {
    let file: String
    let message: String

    init(file: String = "UIScrollEvent.m",
         message: String = "Missing expected nonaccelerated scroll delta") {
        self.file = file
        self.message = message
    }

    func tolerates(_ failure: AssertionFailure) -> Bool {
        failure.raisedIn(file) && failure.message.contains(message)
    }
}

struct CombinedTolerance: AssertionTolerance {
    let parts: [AssertionTolerance]

    func tolerates(_ failure: AssertionFailure) -> Bool {
        parts.contains { $0.tolerates(failure) }
    }
}

final class TolerantAssertionHandler: NSAssertionHandler {
    private let tolerance: AssertionTolerance
    private let onSuppression: (AssertionFailure) -> Void
    private let onEscalation: (AssertionFailure) -> Void

    init(tolerance: AssertionTolerance,
         onSuppression: @escaping (AssertionFailure) -> Void,
         onEscalation: @escaping (AssertionFailure) -> Void) {
        self.tolerance = tolerance
        self.onSuppression = onSuppression
        self.onEscalation = onEscalation
        super.init()
    }

    @objc(handleFailureInMethod:object:file:lineNumber:description:)
    func handleMethodFailure(_ selector: Selector, object: Any?, file: String?, lineNumber: Int, description: String?) {
        route(AssertionFailure.method(selector, object: object, file: file, lineNumber: lineNumber, description: description))
    }

    @objc(handleFailureInFunction:file:lineNumber:description:)
    func handleFunctionFailure(function: String?, file: String?, lineNumber: Int, description: String?) {
        route(AssertionFailure.function(function, file: file, lineNumber: lineNumber, description: description))
    }

    private func route(_ failure: AssertionFailure) {
        if tolerance.tolerates(failure) {
            onSuppression(failure)
        } else {
            onEscalation(failure)
        }
    }
}

enum AssertionShieldActions {
    nonisolated(unsafe) static var raise: @Sendable (AssertionFailure) -> Void = { failure in
        NSException(assertion: failure).raise()
    }

    static func suppress(_ failure: AssertionFailure) {
        shieldLog.warning("*** System assertion suppressed: \(failure.reason, privacy: .public)")
    }

    static func escalate(_ failure: AssertionFailure) {
        shieldLog.error("*** Assertion failure in \(failure.site, privacy: .public), \(failure.file, privacy: .public):\(failure.line) \(failure.message, privacy: .public)")
        raise(failure)
    }
}

enum ScrollAssertionShield {
    static let tolerances: [AssertionTolerance] = [MissingNonAcceleratedScrollDeltaTolerance()]

    static func handler(for tolerances: [AssertionTolerance] = ScrollAssertionShield.tolerances) -> TolerantAssertionHandler {
        TolerantAssertionHandler(tolerance: CombinedTolerance(parts: tolerances),
                                 onSuppression: AssertionShieldActions.suppress,
                                 onEscalation: AssertionShieldActions.escalate)
    }

    @MainActor
    static func install(tolerances: [AssertionTolerance] = ScrollAssertionShield.tolerances) {
        Thread.current.threadDictionary.setObject(handler(for: tolerances), forKey: NSAssertionHandlerKey as NSString)
    }
}
