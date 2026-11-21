import Foundation

@MainActor
final class ChainRun: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var stopRequested = false
    private var token: Int?

    func begin(run: Int = 0) {
        token = run
        stopRequested = false
        isRunning = true
    }

    #if DEBUG
    func requestStop() {
        guard isRunning else { return }
        stopRequested = true
    }
    #endif

    func end(run: Int = 0) {
        guard token == run else { return }
        token = nil
        isRunning = false
        stopRequested = false
    }

    func reset() {
        token = nil
        isRunning = false
        stopRequested = false
    }

    func mayRun(step number: Int, run: Int = 0) -> Bool {
        guard token == run else { return false }
        return number == 1 || !stopRequested
    }
}
