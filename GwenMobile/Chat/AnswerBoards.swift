import GwenMobileKit
import Foundation

@MainActor
final class StreamLease {
    private var owner: Int?
    private var running: Set<Int> = []

    var isBusy: Bool { !running.isEmpty }

    func begin(_ step: Int) -> Bool {
        running.insert(step)
        guard let taken = owner else {
            owner = step
            return true
        }
        return taken == step
    }

    func end(_ step: Int) {
        running.remove(step)
        if owner == step { owner = nil }
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
