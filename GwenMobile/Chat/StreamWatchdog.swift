import GwenMobileKit
import Foundation

struct StreamWatchdog {
    let idle: TimeInterval
    private(set) var sawContent = false
    private(set) var lastContent: ContinuousClock.Instant

    init(idle: TimeInterval = APITimeout.streamIdle, startedAt: ContinuousClock.Instant = .now) {
        self.idle = idle
        self.lastContent = startedAt
    }

    var idleFor: TimeInterval {
        let duration = lastContent.duration(to: .now)
        return TimeInterval(duration.components.seconds)
            + TimeInterval(duration.components.attoseconds) / 1e18
    }

    var stalled: Bool { idleFor > idle }

    mutating func noteContent(at when: ContinuousClock.Instant = .now) {
        lastContent = when
        sawContent = true
    }
}
