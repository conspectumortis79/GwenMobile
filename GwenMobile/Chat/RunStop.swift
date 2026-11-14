import Foundation

enum RunStop {
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if Task.isCancelled { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        return false
    }
}
