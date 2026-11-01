import GwenMobileKit
import Foundation

enum HeadsetMove: Equatable, Sendable {
    case none
    case yield
    case reclaim(preferring: Set<String>)
}

struct RouteChange: Equatable, Sendable {
    let deviceLeft: Bool
    var deviceArrived = false
    let previousBluetooth: Set<String>
    let currentBluetooth: Set<String>
    let available: Set<String>
}

struct HeadsetHandoverPolicy: Equatable, Sendable {
    private(set) var yielded: Set<String> = []
    private(set) var missing: Set<String> = []

    mutating func decide(_ change: RouteChange) -> HeadsetMove {
        if !change.available.isEmpty {
            missing.formUnion(yielded.subtracting(change.available))
            missing.formIntersection(yielded)
            let returned = missing.intersection(change.available)
            if !returned.isEmpty, change.deviceArrived || !returned.isDisjoint(with: change.currentBluetooth) {
                yielded.subtract(returned)
                missing.subtract(returned)
                return .reclaim(preferring: returned)
            }
        }
        let departed = change.previousBluetooth.subtracting(change.currentBluetooth)
        if change.deviceLeft, !departed.isEmpty {
            yielded.formUnion(departed)
            missing.formUnion(departed.subtracting(change.available))
            return .yield
        }
        guard !yielded.isEmpty, !yielded.isDisjoint(with: change.currentBluetooth) else { return .none }
        return .yield
    }
}
