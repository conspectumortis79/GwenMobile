import Foundation

@MainActor
final class StreamLease {
    private var owner: Int?
    private var running: Set<Int> = []
    private var token: Int?

    var isBusy: Bool { !running.isEmpty }

    func begin(_ step: Int, run: Int = 0) -> Bool {
        if token != run {
            token = run
            owner = nil
            running = []
        }
        running.insert(step)
        guard let taken = owner else {
            owner = step
            return true
        }
        return taken == step
    }

    func end(_ step: Int, run: Int = 0) {
        guard token == run else { return }
        running.remove(step)
        if owner == step { owner = nil }
    }

    func clear() {
        token = nil
        owner = nil
        running = []
    }
}

@MainActor
final class StatusLedger {
    private var labels: [Int: String] = [:]

    var text: String? {
        guard let lowest = labels.keys.min() else { return nil }
        return labels[lowest]
    }

    func show(_ label: String, for step: Int) {
        labels[step] = label
    }

    func clear(_ step: Int) {
        labels.removeValue(forKey: step)
    }
}
