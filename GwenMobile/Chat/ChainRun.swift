import Foundation

@MainActor
final class ChainRun: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var stopRequested = false

    func begin() {
        stopRequested = false
        isRunning = true
    }

    func requestStop() {
        guard isRunning else { return }
        stopRequested = true
    }

    func end() {
        isRunning = false
        stopRequested = false
    }

    func mayRun(step number: Int) -> Bool {
        number == 1 || !stopRequested
    }
}
